using System.Text;
using Anthropic;
using Anthropic.Models.Beta.Messages;

namespace HrmsApi.Services;

/// <summary>An AI answer, with what it cost.</summary>
public sealed record AiAnswer(string Text, string? SuggestedPage, int InputTokens, int OutputTokens, int ToolCalls,
    (string Label, string Path)? Download = null);

/// <summary>A previous turn of the chat, sent back by the app for context.</summary>
public sealed record ChatTurn(bool FromUser, string Text);

/// <summary>
/// The AI side of the help chatbot (Claude via the Anthropic API). Optional: it needs an API key,
/// either the company's own (Chatbot → Connect AI, passed in as <c>companyKey</c>) or the server's
/// (env ANTHROPIC_API_KEY). Without one the chatbot answers from the FAQ list only. Any failure (network, limits, refusal, timeout) returns null, and the caller falls
/// back to the FAQ answer, so users never see an AI error.
/// </summary>
public interface IAssistantAi
{
    /// <summary>The server has its own API key (used by companies that haven't connected theirs).</summary>
    bool HasServerKey { get; }
    string Model { get; }
    /// <summary>Can answer with this company's key or, if it has none, the server's.</summary>
    bool CanAnswer(string? companyKey) => !string.IsNullOrWhiteSpace(companyKey) || HasServerKey;
    Task<AiAnswer?> AnswerAsync(string? companyKey, AssistantTools tools, string system, IReadOnlyList<ChatTurn> history,
        string question, CancellationToken ct);
    /// <summary>Tests an API key with a free call. Null = it works; otherwise why not, for the admin.</summary>
    Task<string?> CheckKeyAsync(string apiKey, CancellationToken ct);
}

public sealed class AssistantAi : IAssistantAi
{
    private const int MaxRounds = 6;           // model ↔ tools round trips per question
    private const int MaxTokens = 2048;        // chat answers are short
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(60);

    private readonly string? _serverKey;
    private readonly ILogger<AssistantAi> _logger;
    /// <summary>One client per API key (companies with their own key, and the server's).</summary>
    private readonly System.Collections.Concurrent.ConcurrentDictionary<string, AnthropicClient> _clients = new();

    public bool HasServerKey => _serverKey != null;
    public string Model { get; }

    private AnthropicClient? ClientFor(string? companyKey)
    {
        var key = !string.IsNullOrWhiteSpace(companyKey) ? companyKey.Trim() : _serverKey;
        return key == null ? null : _clients.GetOrAdd(key, k => new AnthropicClient { ApiKey = k });
    }

    public AssistantAi(IConfiguration config, ILogger<AssistantAi> logger)
    {
        _logger = logger;
        var key = config["ANTHROPIC_API_KEY"];
        _serverKey = string.IsNullOrWhiteSpace(key) ? null : key.Trim();
        // Env Assistant__Model to choose another model (e.g. a cheaper one)
        Model = string.IsNullOrWhiteSpace(config["Assistant:Model"]) ? "claude-opus-5-5" : config["Assistant:Model"]!;
    }

    /// <summary>Models that accept server-side refusal fallbacks ("default" routing).</summary>
    private bool SupportsFallbacks =>
        Model.StartsWith("claude-opus-5") || Model.StartsWith("claude-fable-5") || Model == "claude-sonnet-5-5";

    public async Task<string?> CheckKeyAsync(string apiKey, CancellationToken ct)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(TimeSpan.FromSeconds(20));
        try
        {
            // Reading the model's details costs nothing and proves the key and the model work
            var client = new AnthropicClient { ApiKey = apiKey.Trim() };
            await client.Models.Retrieve(Model, cancellationToken: cts.Token);
            return null;
        }
        catch (Anthropic.Exceptions.AnthropicUnauthorizedException)
        {
            return "This API key isn't valid. Check that it was copied completely.";
        }
        catch (Anthropic.Exceptions.AnthropicApiException ex)
        {
            _logger.LogWarning(ex, "AI key check failed");
            return "Anthropic didn't accept this key: " + ex.Message;
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            return "Anthropic didn't answer in time. Please try again.";
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogWarning(ex, "AI key check failed");
            return "Couldn't reach Anthropic from the server. Please try again.";
        }
    }

    public async Task<AiAnswer?> AnswerAsync(string? companyKey, AssistantTools tools, string system, IReadOnlyList<ChatTurn> history,
        string question, CancellationToken ct)
    {
        var client = ClientFor(companyKey);
        if (client == null) return null;
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(Timeout);

        var messages = BuildMessages(history, question);
        var definitions = tools.Definitions();
        int input = 0, output = 0, toolCalls = 0;

        try
        {
            for (var round = 0; round < MaxRounds; round++)
            {
                var request = new MessageCreateParams
                {
                    Model = Model,
                    MaxTokens = MaxTokens,
                    System = system,
                    Messages = messages,
                    Tools = definitions,
                    // Chat answers: low effort keeps them quick and cheap
                    OutputConfig = new BetaOutputConfig { Effort = Effort.Low },
                };
                if (SupportsFallbacks)
                {
                    // A safety-classifier decline is re-run on Anthropic's recommended fallback model
                    request = request with
                    {
                        Betas = ["server-side-fallback-2026-07-01"],
                        Fallbacks = new Default(),
                    };
                }

                BetaMessage response = await client.Beta.Messages.Create(request, cts.Token);
                input += (int)response.Usage.InputTokens;
                output += (int)response.Usage.OutputTokens;

                if (response.StopReason == BetaStopReason.Refusal)
                {
                    _logger.LogInformation("Assistant AI: request declined (refusal)");
                    return null;
                }

                // Echo the assistant turn back unchanged (thinking blocks keep their signatures).
                // After a fallback, blocks before the last fallback marker other than text are left out.
                var lastFallback = -1;
                for (var i = 0; i < response.Content.Count; i++)
                    if (response.Content[i].TryPickFallback(out _)) lastFallback = i;

                var assistant = new List<BetaContentBlockParam>();
                var results = new List<BetaContentBlockParam>();
                var text = new StringBuilder();
                for (var i = 0; i < response.Content.Count; i++)
                {
                    var block = response.Content[i];
                    var beforeFallback = i < lastFallback;
                    if (block.TryPickText(out var t))
                    {
                        assistant.Add(new BetaTextBlockParam { Text = t.Text });
                        if (!beforeFallback) text.Append(t.Text);
                    }
                    else if (block.TryPickFallback(out var fb))
                    {
                        assistant.Add(new BetaFallbackBlockParam { From = new() { Model = fb.From.Model }, To = new() { Model = fb.To.Model } });
                    }
                    else if (beforeFallback)
                    {
                        // thinking / tool calls of the declined attempt are not echoed
                    }
                    else if (block.TryPickThinking(out var th))
                    {
                        assistant.Add(new BetaThinkingBlockParam { Thinking = th.Thinking, Signature = th.Signature });
                    }
                    else if (block.TryPickRedactedThinking(out var rt))
                    {
                        assistant.Add(new BetaRedactedThinkingBlockParam { Data = rt.Data });
                    }
                    else if (block.TryPickToolUse(out var tu))
                    {
                        assistant.Add(new BetaToolUseBlockParam { ID = tu.ID, Name = tu.Name, Input = tu.Input });
                        toolCalls++;
                        string result;
                        var isError = false;
                        try { result = await tools.RunAsync(tu.Name, tu.Input); }
                        catch (Exception ex)
                        {
                            _logger.LogWarning(ex, "Assistant tool {Tool} failed", tu.Name);
                            result = "This information could not be loaded right now.";
                            isError = true;
                        }
                        results.Add(new BetaToolResultBlockParam { ToolUseID = tu.ID, Content = result, IsError = isError });
                    }
                }

                if (response.StopReason != BetaStopReason.ToolUse || results.Count == 0)
                {
                    var answer = text.ToString().Trim();
                    return answer.Length == 0 ? null : new AiAnswer(answer, tools.SuggestedPage, input, output, toolCalls, tools.Download);
                }

                messages.Add(new BetaAssistantMessageParam { Content = assistant });
                messages.Add(new BetaUserMessageParam { Content = results });
            }
            _logger.LogWarning("Assistant AI: no answer after {Rounds} rounds", MaxRounds);
            return null;
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            _logger.LogWarning("Assistant AI: timed out");
            return null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogWarning(ex, "Assistant AI request failed");
            return null;
        }
    }

    /// <summary>
    /// Earlier turns (text only) + the new question. The API needs user/assistant turns to
    /// alternate and start with the user, so the history is tidied up first.
    /// </summary>
    private static List<BetaMessageParam> BuildMessages(IReadOnlyList<ChatTurn> history, string question)
    {
        var turns = new List<ChatTurn>();
        foreach (var t in history.Where(t => !string.IsNullOrWhiteSpace(t.Text)))
        {
            if (turns.Count == 0 && !t.FromUser) continue;
            if (turns.Count > 0 && turns[^1].FromUser == t.FromUser)
                turns[^1] = turns[^1] with { Text = turns[^1].Text + "\n" + t.Text };
            else turns.Add(t);
        }
        if (turns.Count > 0 && turns[^1].FromUser) turns.RemoveAt(turns.Count - 1);   // unanswered question

        var messages = new List<BetaMessageParam>();
        foreach (var t in turns)
            messages.Add(t.FromUser
                ? new BetaUserMessageParam { Content = t.Text }
                : new BetaAssistantMessageParam { Content = t.Text });
        messages.Add(new BetaUserMessageParam { Content = question });
        return messages;
    }
}
