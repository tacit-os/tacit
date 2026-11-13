.pragma library
// Plain arithmetic for the palette's calculator when qalc is not installed. Numbers, + - * / ^ (and
// x or × for times, ÷ for divide), brackets, a trailing %, pi, e and sqrt/abs/ln/log/exp/sin/cos/tan.
// Returns the answer as text, or null when the text is not an expression this understands. As qalc does, a + b% is a
// plus b percent of a (100+10% is 110), and 0x10 is hex, which this does not read, not 0 times 10.

var funcs = {
    sqrt: Math.sqrt, abs: Math.abs, ln: Math.log, log: Math.log10, exp: Math.exp,
    sin: Math.sin, cos: Math.cos, tan: Math.tan
};

function evaluate(text) {
    if (/(^|[^\w.])0x[\da-f]/i.test(String(text)))
        return null;
    var s = String(text).replace(/([\d)])\s*x\s*(?=[\d(.])/gi, "$1*").replace(/\s+/g, "").replace(/×/g, "*").replace(/÷/g, "/").replace(/\*\*/g, "^").replace(/π/g, "pi");
    if (s.length === 0 || s.length > 200)
        return null;
    var pos = 0;
    var depth = 0;
    // where the last % was read, and whether the term product() just read was one percentage alone (10%, (5+5)%)
    var pctEnd = -1;
    var bare = false;

    function peek() { return s.charAt(pos); }
    function fail() { throw new Error("syntax"); }

    function sum() {
        var v = product();
        while (peek() === "+" || peek() === "-") {
            var op = s.charAt(pos++);
            var r = product();
            if (bare)
                r = v * r;
            v = op === "+" ? v + r : v - r;
        }
        return v;
    }
    function product() {
        var v = signed();
        var alone = true;
        while (peek() === "*" || peek() === "/") {
            alone = false;
            var op = s.charAt(pos++);
            var r = signed();
            v = op === "*" ? v * r : v / r;
        }
        bare = alone && pctEnd === pos;
        return v;
    }
    function signed() {
        if (peek() === "-") { pos++; return -signed(); }
        if (peek() === "+") { pos++; return signed(); }
        return power();
    }
    function power() {
        var base = percent();
        if (peek() === "^") {
            pos++;
            var v = Math.pow(base, signed());
            pctEnd = -1;
            return v;
        }
        return base;
    }
    function percent() {
        var v = atom();
        while (peek() === "%") { pos++; v = v / 100; pctEnd = pos; }
        return v;
    }
    function atom() {
        var c = peek();
        if (c === "(") {
            if (++depth > 20) fail();
            pos++;
            var v = sum();
            if (peek() !== ")") fail();
            pos++;
            depth--;
            return v;
        }
        var m = /^(\d+\.?\d*|\.\d+)(e[+-]?\d+)?/i.exec(s.slice(pos));
        if (m) { pos += m[0].length; return parseFloat(m[0]); }
        var w = /^[a-z]+/i.exec(s.slice(pos));
        if (!w) fail();
        var name = w[0].toLowerCase();
        pos += name.length;
        if (name === "pi") return Math.PI;
        if (name === "e") return Math.E;
        if (funcs[name] === undefined || peek() !== "(") fail();
        return funcs[name](atom());
    }

    var result;
    try {
        result = sum();
        if (pos !== s.length) return null;
    } catch (e) {
        return null;
    }
    if (typeof result !== "number" || !isFinite(result))
        return null;
    // 0.1 + 0.2 should read 0.3: keep twelve significant digits
    return String(parseFloat(result.toPrecision(12)));
}
