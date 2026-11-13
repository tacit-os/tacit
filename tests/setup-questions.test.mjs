// Setup's questions (setup.qml): its own forward() and afterQuestions() run under node from the "you" page, with a
// pretend backend that keeps what it is sent. Nothing reads an answer about reports yet, so Setup does not ask one and
// tacit-install writes none.
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Setup's questions (setup.qml)");
const src = read("setup.qml");
const forward = qmlFunction(src, "forward"), after = qmlFunction(src, "afterQuestions");
const pages = [], sent = [];
const setup = { page: "you", installState: "running", joined: "", network: "Home", language: "en_GB", kbLayout: "us",
  place: "next", picture: "dune", reports: false, go(p) { pages.push(p); this.page = p; } };
const scope = { setup, backend: { send: m => sent.push(m) }, nameField: { text: "Sam" }, passField: { text: "pw" } };
scope.root = { primaryLater: false, afterQuestions: inScope(scope, after.params, after.body) };
inScope({ ...scope, shownPage: "you" }, forward.params, forward.body)();

check("Continue on the \"you\" page goes on to the last page, with no question about reports",
  JSON.stringify(pages) === '["almost"]', `went to ${JSON.stringify(pages)}`);
check("the answers sent to the installer hold no reports answer",
  sent.length === 1 && sent[0].op === "answers" && !("reports" in sent[0]), JSON.stringify(sent));
check("tacit-install writes no answer to /var/lib/tacit/reports",
  !/open\([^)]*var\/lib\/tacit\/reports/.test(read("scripts/setup/tacit-install")));
done();
