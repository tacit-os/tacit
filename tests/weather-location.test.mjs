// The weather map's GPS marker (modules/common/widgets/WorldMap.qml's gpsFixValid) when a fix arrives while the map is
// on screen (services/Weather.qml's PositionSource handlers): the handlers run under node, and the map's binding is
// evaluated again only when Weather.location is assigned, as QML does for a var property (setting one of its fields
// says nothing).
import { inScope, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the weather map follows the GPS fix (Weather.location)");
const weather = read("services/Weather.qml"), map = read("modules/common/widgets/WorldMap.qml");
const at = weather.indexOf("sourceComponent: PositionSource");
const handler = name => readExpression(weather, weather.indexOf(`${name}:`, at) + name.length + 1).expr.slice(1, -1);

function session() {
  let location = { valid: false, lat: 0, lon: 0 }, notified = 0;
  const Weather = { gpsActive: true, gpsFailed: false, getData() {},
    get location() { return location; }, set location(v) { location = v; notified++; onLocation(); } };
  // the map's binding, kept as QML keeps it: worked out at the start and again on locationChanged
  const gpsFixValid = inScope({ Weather }, "", `return (${qmlProperty(map, "gpsFixValid")});`);
  let shown = gpsFixValid();
  const onLocation = () => (shown = gpsFixValid());
  const scope = { root: Weather, gpsAcquisition: { stop() {} }, Qt: { callLater: f => f() }, console: { error() {} },
    PositionSource: { NoError: 0 }, positionSource: { sourceError: 0, valid: true, stop() {} } };
  return {
    fix(lat, lon) {
      scope.position = { latitudeValid: true, longitudeValid: true, coordinate: { latitude: lat, longitude: lon } };
      inScope(scope, "", handler("onPositionChanged"))();
    },
    lose() { scope.positionSource.sourceError = 1; inScope(scope, "", handler("onSourceErrorChanged"))(); },
    get shown() { return shown; }, get notified() { return notified; }, Weather,
  };
}

{
  const s = session();
  s.fix(48.85, 2.35);
  check("a fix that arrives with the map on screen moves its marker to the fix", s.shown === true,
    `the map still says no fix (Weather.location told ${s.notified} times)`);
  check("and the fix is what Weather holds", s.Weather.location.valid === true && s.Weather.location.lat === 48.85 && s.Weather.location.lon === 2.35,
    JSON.stringify(s.Weather.location));
  s.lose();
  check("a fix lost afterwards is said too", s.Weather.location.valid === false && s.notified >= 2, `${JSON.stringify(s.Weather.location)}, told ${s.notified} times`);
}

done();
