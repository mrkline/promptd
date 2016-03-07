module promptoglyph.path;

// Explicitly specify what we're importing from each module.
// I don't usually do this, but the argument for it is that
// it makes it easier to keep track of what each import is here for.
// It's similar to Python's "from x import y"
import std.algorithm : map, startsWith;
import std.array : array;
import std.datetime : msecs;
import std.file : getcwd;
import std.getopt;
import std.path : pathSplitter;
import std.process : environment;
import std.range : empty, take;
import std.traits : isSomeString;
import std.utf : count, stride;
import std.stdio;

import help;

// NOTE(dkg): see systempath.d and git.d for details about this
version (Windows) version = PathFixNeeded;
version (Cygwin) version = PathFixNeeded;

import std.path : customBuildPath = buildPath;


void main(string[] args)
{
	import std.exception : ifThrown;
	import std.stdio : write;

	int shortenAt = 0;
	int shortenNumChars = 1;

	try {
		getopt(args,
			config.caseSensitive,
			config.bundling,
			"help|h", { writeAndSucceed(helpString); },
			"version|v", { writeAndSucceed(versionString); },
			"shorten-at-length|s", &shortenAt,
			"shorten-to-num-chars|n", &shortenNumChars);
	}
	catch (GetOptException ex) {
		writeAndFail(ex.msg, "\n", helpString);
	}

	// NOTE(dkg): on Windows (under Cygwin even) env["HOME"] will include
	//            the drive letter and the path is a Windows style path
	// Another problem is that home and cwd will result in
	// home, cwd: C:\Cygwin\home\dkg, C:\Users\dkg\Projekte\d\promptd
	// in Cygwin, so the homeToTilde function will not work here.
	// When you convert both paths via cygpath to Unix style path they are 
	// different as well:
	// home, cwd: /home/dkg, /cygdrive/c/Users/dkg/Projekte/d/promptd
	version(PathFixNeeded)
	{
		import std.process : execute;
		import std.string : strip, indexOf;
		import std.array : replace;

		bool isCygWinEnv = environment.get("SHELL", "") != "" && 
			environment.get("TERM", "") != "";
		string home = environment["HOME"].ifThrown("");
		string cwd  = getcwd().ifThrown(environment["PWD"]).ifThrown("???");

		if (isCygWinEnv && home.indexOf(":") > -1) {
			// sigh, yeah, see NOTE above as to why
			// I want to get the real Unix style path here from Cygwin,
			// not the Windows style one.
			auto homePath = execute(["cygpath", "-u", home]);
			home = homePath.output.strip();
			auto cwdPath = execute(["cygpath", "-u", cwd]);
			cwd = cwdPath.output.strip().replace("\\", "/");
		}
	}
	else
	{
		immutable string home = environment["HOME"].ifThrown("");
		immutable string cwd = getcwd().ifThrown(environment["PWD"]).ifThrown("???");
	}

	string path = homeToTilde(cwd, home);
	if (path.count >= shortenAt)
		path = shorten(path, shortenNumChars);

	version (PathFixNeeded)
	{
		if (isCygWinEnv && path.indexOf("\\") > -1)
			path = path.replace("\\", "/");
	}

	write(path);
}

string versionString = q"EOS
promptoglyph-path by Matt Kline, version 0.5
Part of the promptoglyph tool set
EOS";

string helpString = q"EOS
usage: promptoglyph-path [-s <length>]

Options:

  --help, -h
    Display this help text

  --version, -v
    Display the version info

  --shorten-at-length, -s <length>
    Shorten the path if it exceeds <length>.
    Defaults to 0 (always shorten)

  --shorten-to-num-chars, -n <length>
    When shortening, keep <length> characters in shortened path.
    Defaults to 1 (keep first character)

promptoglyph-path is designed to be part of a shell prompt.
It prints your current path, shortened in a similar manner to paths in fish.
If you only want to shorten paths longer than a given length, use
--shorten-at-length.
EOS";

// TODO: Parse /etc/passwd so that this works with other users'
//       home directories as well.
pure string homeToTilde(string cwd, string home)
{
	if (!home.empty && cwd.startsWith(home))
		return "~" ~ cwd[home.length .. $];
	else
		return cwd;
}

pure string shorten(string path, int numChars = 1)
{
	auto pathTokens = pathSplitter(path).array;
	
	if (pathTokens.length < 2)
		return path;

	// We never shorten the last part of the path
	auto last = pathTokens[$-1];
	auto rest = pathTokens[0 .. $-1];

	// If we have a home directory at the start, don't shorten that.
	if (rest[0].startsWith("~"))
		rest = rest[0] ~ rest[1 .. $].map!(s => firstOf(s, numChars)).array;
	else
		rest = rest.map!(s => firstOf(s, numChars)).array;

	return customBuildPath(rest ~ last);
}

unittest
{
	assert(shorten("foo") == "foo");
	assert(shorten("/foo/bar/baz") == "/f/b/baz");
	assert(shorten("~foo/bar/baz") == "~foo/b/baz");
	assert(shorten("foo", 2) == "foo");
	assert(shorten("/foo/bar/baz", 2) == "/fo/ba/baz");
	assert(shorten("~foo/bar/baz", 2) == "~foo/ba/baz");
	assert(shorten("foo", 99) == "foo");
	assert(shorten("/foo/bar/baz", 99) == "/foo/bar/baz");
	assert(shorten("~foo/bar/baz", 99) == "~foo/bar/baz");
}

// Takes a string and returns its first character,
// as a string
pure auto firstOf(S)(S s, int numChars = 1) if (isSomeString!S)
in
{
	assert(!s.empty);
}
body
{
	import std.conv : to;

	// We use take so that this plays nicely
	// with non-ASCII file names.
	if (numChars > s.length)
		return s.to!S;
	else
		return s.take(numChars).to!S;
}

unittest
{
	assert(firstOf("ASCII") == "A");
	assert(firstOf("漢字") == "漢");
	assert(firstOf("ASCII", 2) == "AS");
	assert(firstOf("漢字漢字", 2) == "漢字");
	assert(firstOf("ASCII", 99) == "ASCII");
	assert(firstOf("漢字漢字", 99) == "漢字漢字");
}
