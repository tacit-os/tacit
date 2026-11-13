// A second "New file" in a Pinax folder is "Untitled 2.txt", still a .txt (modules/ii/files/FilesWindow.qml): the
// window's own newFile, newFolder, freeName and nameTaken run under node in folders that already hold the first ones.
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== New file names the next one before its extension (FilesWindow.qml)");
const src = read("modules/ii/files/FilesWindow.qml");
function made(names, what) {
  const ran = [];
  const win = { folder: "/home/a/Notes", names: Object.fromEntries(names.map(n => [n, true])), run: (op, args) => ran.push(args[1]) };
  for (const name of ["newFile", "newFolder", "freeName", "nameTaken"]) {
    const f = qmlFunction(src, name);
    win[name] = inScope({ win }, f.params, f.body);
  }
  win[what]();
  return ran[0];
}
check("the first New file is Untitled.txt", made([], "newFile") === "Untitled.txt", made([], "newFile"));
check("the second is Untitled 2.txt", made(["Untitled.txt"], "newFile") === "Untitled 2.txt", made(["Untitled.txt"], "newFile"));
check("the third is Untitled 3.txt", made(["Untitled.txt", "Untitled 2.txt"], "newFile") === "Untitled 3.txt", made(["Untitled.txt", "Untitled 2.txt"], "newFile"));
check("New folder still counts as before", made(["New folder"], "newFolder") === "New folder 2", made(["New folder"], "newFolder"));
done();
