// What Praxis says of an account that cannot start a session yet (modules/claude/AccountsModel.qml, Composer.qml,
// AgentSteps.qml, PrefsSheet.qml, and the Settings app's account row): the state agent-host pushes, in words, with a way
// on. The files' own functions and bindings run under node with a pretend host.
import { inScope, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const accSrc = read("modules/claude/AccountsModel.qml"), boxSrc = read("modules/claude/Composer.qml");
const stepsSrc = read("modules/claude/AgentSteps.qml"), prefsSrc = read("modules/claude/PrefsSheet.qml");
const block = (src, name) => { const e = qmlProperty(src, name); return e === null ? "return undefined;" : e.startsWith("{") ? e.slice(1, -1) : `return (${e});`; };
const value = (src, name, scope) => inScope(scope, "", block(src, name))();

// the model as agent-host's state push leaves it: one Claude account that signs in with an Anthropic key
function model(state) {
  const account = { id: "k1", agent: "claude", label: "Work key", use: "key", key: "key-1", state };
  const acc = { agents: { claude: { installed: true } }, install: null, installSeen: true, node: true, keys: [{ id: "key-1", provider: "anthropic", last4: "4f2a" }],
    providers: [], accounts: [account], agentOrder: ["claude"], checked: [],
    account: id => (id === "k1" ? account : null), defaultAccount: () => account, accountsOf: () => [account],
    agentName: () => "Claude Code", check: id => acc.checked.push(id) };
  for (const f of ["stepOf", "stepWord", "factsOf", "planWords", "providerName", "keyProvider"]) {
    const q = qmlFunction(accSrc, f);
    acc[f] = inScope({ acc, Qt: { formatDate: () => "" } }, q.params, q.body);
  }
  Object.defineProperty(acc, "needs", { get: () => value(accSrc, "needs", { acc }) });
  return acc;
}

console.log("What Praxis says of an account that needs a step (modules/claude/AccountsModel.qml, Composer.qml, AgentSteps.qml)");

// later-praxis-1 [3] a key account whose keyring is not running (no Secret Service answered): agent-host says noKeyring,
// and Praxis had no word for it: no facts on the row, no step in the box, nothing in the cove, and Send failed on an error line
{
  const acc = model("noKeyring");
  const facts = acc.factsOf("claude", "k1"), needs = acc.needs;
  const box = fresh => {
    const composer = { hasAccounts: true, accounts: acc, agent: "claude", acctId: "k1", fresh, agentLabel: "Claude Code" };
    Object.defineProperty(composer, "step", { get: () => value(boxSrc, "step", { composer }) });
    return { needs: value(boxSrc, "needsStep", { composer }), line: value(boxSrc, "stepLine", { composer }) };
  };
  const newOne = box(true), started = box(false);
  check("the row says the keyring isn't running, and the account is among those that need a step",
    /keyring/i.test(facts) && needs.length === 1 && needs[0].step === "noKeyring", `facts "${facts}", needs ${JSON.stringify(needs)}`);
  check("a new session's box holds the message and says why; a started one, whose process may hold the key, sends",
    newOne.needs === true && /keyring/i.test(newOne.line) && started.needs === false, `new ${JSON.stringify(newOne)}, started ${JSON.stringify(started)}`);

  const steps = { agent: "claude", accountId: "k1", shown: "noKeyring", acct: acc.account("k1"), refusal: null, flow: null, model: acc,
    settingsRequested() {}, checkAgain() {}, cancelSignIn() {}, keyAnchor: p => p };
  const view = value(stepsSrc, "view", { steps, Qt: {}, Quickshell: {} });
  const again = (view.actions ?? []).find(a => a.word === "Check again");
  if (again) again.run();
  check("the agent cove's step says so, with Check again, which asks the host to read the keyring again",
    /keyring/i.test(view.line ?? "") && !!again && JSON.stringify(acc.checked) === '["k1"]', `${JSON.stringify(view.line)}, asked ${JSON.stringify(acc.checked)}`);

  const sheet = { needs, accounts: acc };
  const line = value(prefsSrc, "needLine", { sheet }), anchor = value(prefsSrc, "needAnchor", { sheet });
  check("the preferences sheet names it too, with no Settings link that has nothing to set", /keyring/i.test(line) && anchor === "", `"${line}", anchor "${anchor}"`);

  // the owner's words (r3): what to do about it, not only what is wrong; the Settings app's row had none
  const said = "The keyring isn't running. Sign out and in again to start it.";
  const settings = read("tacit-settings.qml"), accPage = { accounts: [acc.account("k1")] };
  for (const f of ["facts", "accountsOf", "defaultOf", "planText", "providerName", "keyProvider"]) {
    const q = qmlFunction(settings, f);
    if (q) accPage[f] = inScope({ accPage, Qt: { formatDate: () => "" } }, q.params, q.body);
  }
  const row = accPage.facts ? accPage.facts(acc.account("k1")) : "";
  check("the box and the cove say how to start it, and so does the Settings app's account row",
    newOne.line === said && `${view.line}. ${view.sub}.` === said && row === said, `box "${newOne.line}", cove "${view.line}" / "${view.sub}", Settings "${row}"`);
}

// later-praxis-1 [9] a key marked refused (one provider hiccup is enough) or missing offered only Replace in Settings,
// though the host's account_check asks the provider about the key again: a good key was typed in again
{
  const shown = state => {
    const acc = model(state);
    const steps = { agent: "claude", accountId: "k1", standing: state, pending: "", acct: acc.account("k1"), refusal: null, flow: null,
      finishing: false, codeOpen: false, model: acc, settings: [], settingsRequested: a => steps.settings.push(a), cancelSignIn() {}, esc: s => s };
    const scope = { steps, Qt: {}, Quickshell: {}, checkWait: { restart() {} } };
    for (const f of ["keyAnchor", "owes", "checkAgain"]) { const q = qmlFunction(stepsSrc, f); if (q) steps[f] = inScope(scope, q.params, q.body); }
    Object.defineProperty(steps, "shown", { get: inScope(scope, "", block(stepsSrc, "shown")) });
    const view = () => inScope(scope, "", block(stepsSrc, "view"))();
    const words = (view().actions ?? []).map(a => a.word);
    (view().actions ?? []).find(a => a.word === "Check again")?.run();
    return { words, checked: acc.checked, during: steps.shown };
  };
  const refused = shown("keyRefused"), none = shown("noKey");
  check("a refused or missing key offers Check again beside Replace in Settings, which asks the host and says Checking…",
    [refused, none].every(r => JSON.stringify(r.words) === '["Replace in Settings","Check again"]' && JSON.stringify(r.checked) === '[""]' && r.during === "checking"),
    `refused ${JSON.stringify(refused)}, no key ${JSON.stringify(none)}`);
}

// decisions2 a2 (the owner's): agent-host gets Node.js as the Apps window gets an app, and refuses while system updates
// wait; the cove showed the refusal with only Install both, which could not work until the system was updated
{
  const view = line => {
    const acc = model("ready");
    acc.install = { agent: "claude", step: "failed", line };
    const opened = [];
    const steps = { agent: "claude", accountId: "k1", shown: "needsNode", acct: acc.account("k1"), refusal: null, flow: null, model: acc,
      settingsRequested() {}, checkAgain() {}, cancelSignIn() {}, install() {} };
    const v = value(stepsSrc, "view", { steps, Qt: {}, Quickshell: {}, SettingsApp: { open: page => opened.push(page) } });
    const words = (v.actions ?? []).map(a => a.word);
    (v.actions ?? []).find(a => a.word === "Open Updates")?.run();
    return { mono: v.mono, words, opened };
  };
  const waits = view("Node.js needs a system update first"), other = view("npm error 404 Not Found");
  check("Node.js refused while updates wait: the line offers Open Updates, which opens Settings at Updates; another failure does not",
    waits.mono === "Node.js needs a system update first" && waits.words[0] === "Open Updates" && JSON.stringify(waits.opened) === '["about:updates"]'
      && waits.words.includes("Install both") && !other.words.includes("Open Updates"),
    `refused ${JSON.stringify(waits)}, other ${JSON.stringify(other)}`);
}

// later-agent-host-2 [8] and decisions3-agent-host [2] (h8, h11): the code step agent-host sends carries the page that
// shows the code (`url`, Claude Code's printed manual page; for opencode 2 the new attempt's) and why it asks again
// (`message`); Praxis showed the field alone, and after a refused paste it said "Checking the code…" until its own 20 s
{
  const manual = "https://claude.ai/oauth/authorize?code=true&state=s1";
  const cove = (flow, checking = false) => {
    const acc = model("signingIn");
    const opened = [];
    const steps = { agent: "claude", accountId: "k1", shown: "code", acct: acc.account("k1"), refusal: null, flow, model: acc, checkingCode: checking,
      pending: "", settingsRequested() {}, checkAgain() {}, cancelSignIn() {}, finish() {} };
    const v = value(stepsSrc, "view", { steps, Qt: { openUrlExternally: u => opened.push(u) }, Quickshell: {} });
    (v.actions ?? []).find(a => a.word === "Open the page")?.run();
    return { field: v.field ?? false, sub: v.sub ?? "", words: (v.actions ?? []).map(a => a.word), opened };
  };
  const refused = cove({ step: "code", account: "k1", url: manual, message: "Invalid code. Please make sure the full code was copied." });
  const again = cove({ step: "code", account: "k1", url: "https://claude.ai/oauth/authorize?state=s2", message: "That code didn't work. Here's a new page to sign in again." });
  const bare = cove({ step: "code", account: "k1" }), early = cove({ step: "waiting", account: "k1", url: "http://localhost:5173/callback" });
  check("the code step links its page with Open the page and says why it asks again; with no page, or before the host asks, no link",
    refused.field && JSON.stringify(refused.opened) === JSON.stringify([manual]) && /Invalid code/.test(refused.sub)
      && again.sub === "That code didn't work. Here's a new page to sign in again." && again.opened[0] === "https://claude.ai/oauth/authorize?state=s2"
      && !bare.words.includes("Open the page") && !early.words.includes("Open the page") && early.sub === "",
    `refused ${JSON.stringify(refused)}, opencode 2 ${JSON.stringify(again)}, none ${JSON.stringify(bare)}, waiting ${JSON.stringify(early)}`);

  const m = /\bonFlowChanged:\s*/.exec(stepsSrc);
  const onFlow = m ? readExpression(stepsSrc, m.index + m[0].length).expr : "{}";
  const after = step => {
    const steps = { flow: { step, account: "k1" }, pending: "", checkingCode: true, finish() {} };
    inScope({ steps }, "", onFlow.slice(1, -1))();
    return steps.checkingCode;
  };
  check("a code step pushed while a pasted code is checked ends the checking, so the field and the words come back at once",
    after("code") === false && after("waiting") === true, `after a code step ${after("code")}, after waiting ${after("waiting")}`);
}

done();
