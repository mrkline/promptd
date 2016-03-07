import std.stdio;
import std.process;
import std.string : startsWith, strip, indexOf;
import std.array : replace;
import core.vararg;

// On Windows the following can happen:
//
// The user has installed git normally via Chocolately or MSI package
// so it can be used in cmd.exe. The user also has git installed
// as part of Cygwin via the Cygwin package manager.
// 
// Depending on which one is called the output of the following command 
// to get the project's root folder
//
//    auto rootFinder = execute(["git", "rev-parse", "--show-toplevel"]);
//
// is either C:\path\to\repro or /path/to/repro.
//
// If the cmd.exe version is called within a Cygwin terminal or vice-versa
// then all kinds of things go wrong with file and directory access.
//
// The problem is that D's standard library uses the 
//    version(Windows) { ... Win32 API calls ... }
//    version(Posix) { ... Posix calls ... }
// compiler directives to provide file access and read/write files.
// So internally it uses the Win32 API on Windows which expects C:\path style
// paths, unlike what Cygwin's git version gives us, which is /path style paths.
//
// So the file reading comes down crashing.
//
// If I compile in Cyginw then everything works as expected?
// No, unfortunately not, if the D compiler is installed using the MSI package
// (that is, it is not a Cygwin package). Not sure what would happen if you 
// installed D via a Cygwin package or even compile it from source in Cygwin though.
// Feel free to investigate that route.
//
// The solution for this case (Cygwin git, compiled promptoglyph-vcs.exe with 
// dmd.exe installed via non-cygwin-package, executing within Cygwin) is to
// convert the Unix style path to a Windows style one with the handy cygpath
// tool.
//
version (Windows) version = PathFixNeeded;
version (Cygwin) version = PathFixNeeded;

private:

bool isCygWinEnv = false;
bool testedForCygwin = false;

version (PathFixNeeded)
{
	import std.path : buildNormalizedPath;
	// Runtime Cygwin detection
	// NOTE(dkg): If you have a cleaner/better solution, please let me know. Thanks.
	//
	// UID is empty even in cygwin???
	// HOME is C:\Cygwin\home\<user> and not (as expected) /home/<user>
	//
	//void environmentTest()
	//{
	//	writeln("UID is   ",  environment.get("UID",   "empty"));
	//	writeln("HOME is  ",  environment.get("HOME",  "empty"));
	//	writeln("SHELL is ",  environment.get("SHELL", "empty"));
	//	writeln("TERM is  ",  environment.get("TERM",  "empty"));
	//}

	// NOTE(dkg): While this works, it is not particularly elegant.
	//            Maybe this could be improved by using program arguments
	//            instead to force a particular path style? So in
	//            Cygwin's bash you would pass something like "--cygwin"
	//            and then would just convert the paths always, so the 
	//            dynamic check during runtime would not be needed.
	public string customBuildPath(...)
	{
		if (!testedForCygwin) {
			// NOTE(dkg): If you know a better way to check during runtime
			//            whether or not we are in a Cygwin shell, then please
			//            let me know.
			isCygWinEnv = environment.get("SHELL", "") != "" && 
				environment.get("TERM", "") != "";
			testedForCygwin = true;
		}

		string s = "";
		for (int i = 0; i < _arguments.length; i++)
		{
			if (_arguments[i] == typeid(string[])) {
				string[] elements = va_arg!(string[])(_argptr);
				foreach (element; elements)
				{
					s = buildNormalizedPath(s, element);
				}
			} else {
				string element = va_arg!(string)(_argptr);
				s = buildNormalizedPath(s, element);
			}
		}
		if (isCygWinEnv) {
			// on cygwin - replace \ with /
			// also make sure that we convert the path to a Windows path
			// that means convernt /path to C:\path
			if (s.indexOf(":") <= -1) {
				s = s.replace("\\", "/");	
				if (s.startsWith("/")) {
					auto pathConversion = execute(["cygpath", "-w", s]);
					if (pathConversion.status != 0) {
						writeln("path could not be converted to Windows compatible path: ", s);
						assert(0); // force crash
					}
					s = pathConversion.output.strip();
				} else {
					//writeln("path is not an absolute path: ", s);
					//assert(0); // force crash
				}
			}
		}
		return s;
	} // customBuildPath

}
else
{
	//import std.path : customBuildPath = buildPath;
}

