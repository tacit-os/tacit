// Where the weather map in Settings puts its marker for the city typed in Settings > Services
// (modules/common/widgets/WorldMap.qml, findCityCoords() over WorldCities.js): its own code under node.
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the weather map's marker for a city (WorldMap.findCityCoords)");
const cityCoords = new Function(`${read("modules/common/widgets/WorldCities.js").replace(/^\.pragma.*$/m, "")}\nreturn cityCoords;`)();
const f = qmlFunction(read("modules/common/widgets/WorldMap.qml"), "findCityCoords");
const find = inScope({ WorldCities: { cityCoords } }, f.params, f.body);
const nameOf = c => (c ? Object.keys(cityCoords).find(n => cityCoords[n] === c) : null);

for (const [typed, want] of [
  ["São Paulo", "sao paulo"], ["Zürich", "zurich"], ["Bogotá", "bogota"], ["Montréal", "montreal"], ["Medellín", "medellin"],
  ["London, UK", "london"], ["Paris, France", "paris"], ["Santiago de Chile", "santiago"], ["New York City", "new york"],
  ["Ho Chi Minh", "ho chi minh city"], ["  Tokyo ", "tokyo"],
  ["Nice", null], ["Romeo", null], ["Lim", null], ["", null], [", ", null],
]) {
  const got = nameOf(find(typed));
  check(`"${typed}" ${want ? `puts the marker on ${want}` : "puts no marker"}`, got === want, `it went on ${got}`);
}

done();
