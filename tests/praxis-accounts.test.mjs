// What Praxis says of an account that cannot start a session yet (modules/claude/AccountsModel.qml, Composer.qml,
// AgentSteps.qml, PrefsSheet.qml): the state agent-host pushes, in words, with a way on. The files' own functions and
// bindings run under node with a pretend host.
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
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

done();
