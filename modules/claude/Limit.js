// What a session stopped by its plan's usage limit says, the same in the rail, the header and the notch: "Limit
// reached · back at 14:00", the day named first when it is not today; with no time known, "Limit reached". The time is
// agent-host's limited.resetsAt, in unix seconds as Claude Code gives it (milliseconds, as the host's other times are,
// read the same).
.pragma library

const weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

function words(resetsAt, now) {
    const n = Number(resetsAt) || 0;
    if (n <= 0) return "Limit reached";
    const d = new Date(n > 1e11 ? n : n * 1000), t = new Date(now ?? Date.now());
    const hm = `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
    // whole days between the two midnights (a day across a clock change is 23 or 25 hours)
    const days = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - new Date(t.getFullYear(), t.getMonth(), t.getDate())) / 86400000);
    const when = days <= 0 ? `at ${hm}` : days === 1 ? `tomorrow at ${hm}`
        : days < 7 ? `on ${weekdays[d.getDay()]} at ${hm}` : `on ${d.getDate()} ${months[d.getMonth()]} at ${hm}`;
    return `Limit reached · back ${when}`;
}

// the words for a session's live state, or "" when it is not limited (a host that does not say, too)
function of(live, now) {
    return live?.limited ? words(live.limited.resetsAt, now) : "";
}
