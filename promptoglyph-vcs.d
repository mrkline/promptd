module promptoglyph.vcs;

import std.getopt;
import std.datetime : msecs;
import std.stdio : write;
import std.array : replace;

import color;
import git;
import help;
import vcs;

// TODO(dkg): somehow fix the unicode support on Windows' cmd.exe
// cmd.exe does not support fancy unicode chars in the output for whatever reason
// see http://stackoverflow.com/questions/14109024/how-to-make-unicode-charset-in-cmd-exe-by-default
// Another thing is that cmd.exe is not really suited for this tool anyway, but Powershell is, so we
// should see if we can add fancy unicode chars for powershell users.
// Maybe use program arguments again, like we already do for coloring or
// bash/zsh specific escape codes.

version(Windows)
{
	const string defaultIndexedText = "i";
	const string defaultModifiedText = "m";
	const string defaultUntrackedText = "u";
} 
else
{
	const string defaultIndexedText = "✔";
	const string defaultModifiedText = "±";
	const string defaultUntrackedText = "?";
}

struct StatusStringOptions {
	string prefix = "[";
	string suffix = "]";
	string indexedText = defaultIndexedText;
	string modifiedText = defaultModifiedText;
	string untrackedText = defaultUntrackedText;
}

void main(string[] args)
{
	uint timeLimit = 500;
	bool noColor;
	bool bash, zsh;
	StatusStringOptions stringOptions;

	try {
		getopt(args,
			config.caseSensitive,
			config.bundling,
			"help|h", { writeAndSucceed(helpString); },
			"version|v", { writeAndSucceed(versionString); },
			"time-limit|t", &timeLimit,
			"prefix|p", &stringOptions.prefix,
			"indexed-text|i", &stringOptions.indexedText,
			"modified-text|m", &stringOptions.modifiedText,
			"untracked-text|u", &stringOptions.untrackedText,
			"suffix|s", &stringOptions.suffix,
			"no-color", &noColor,
			"bash|b", &bash,
			"zsh|z", &zsh);
	}
	catch (GetOptException ex) {
		writeAndFail(ex.msg, "\n", helpString);
	}

	if (bash && zsh)
		writeAndFail("Both --bash and --zsh specified. Wat.");

	Escapes escapesToUse;
	version(Windows) {
		escapesToUse = Escapes.cmd;
	} else version(Posix) {
		if (bash)
			escapesToUse = Escapes.bash;
		else if (zsh)
			escapesToUse = Escapes.zsh;
		else // Redundant (none is the default), but more explicit.
			escapesToUse = Escapes.none;
	}

	const Duration allottedTime = timeLimit.msecs;

	const RepoStatus* status = getRepoStatus(allottedTime);

	string statusString = stringRepOfStatus(
		status, stringOptions,
		noColor ? UseColor.no : UseColor.yes,
		escapesToUse,
		allottedTime);

	write(statusString);
}

/**
 * Gets a string representation of the status of the Git repo
 *
 * Params:
 *   allottedTime = The amount of time given to gather Git info.
 *                  Git status will be killed if it does not complete in this much time.
 *                  Since this is for a shell prompt, responsiveness is important.
 *   colors = Whether or not colored output is desired
 *   escapes = Whether or not ZSH escapes are needed. Ignored if no colors are desired.
 *
 */
string stringRepOfStatus(const RepoStatus* status, const ref StatusStringOptions stringOptions,
                         UseColor colors, Escapes escapes, Duration allottedTime)
{
	import time;

	if (status is null)
		return "";

	// Local function that colors a source string if the colors flag is set.
	string colorText(string source,
	                 string function(Escapes) colorFunction)
	{
		if (!colors)
			return source;
		else
			return colorFunction(escapes) ~ source;
	}

	string head;

	if (!status.head.empty)
		head = colorText(status.head, &cyan);

	string flags = " ";

	if (status.flags.indexed)
		flags ~= colorText(stringOptions.indexedText, &green);
	if (status.flags.modified)
		flags ~= colorText(stringOptions.modifiedText, &yellow); // Yellow plus/minus
	if (status.flags.untracked)
		flags ~= colorText(stringOptions.untrackedText, &red); // Red quesiton mark

	// We don't want an extra space if there's nothing to show.
	if (flags == " ")
		flags = "";

	string ret = head ~ flags ~
	             colorText(stringOptions.suffix, &resetColor);

	if (pastTime(allottedTime))
		ret = "T " ~ ret;

	return stringOptions.prefix ~ ret;
}

const string versionString = q"EOS
promptoglyph-vcs by Matt Kline, version 0.5
Part of the promptoglyph tool set
EOS";

const string helpStringTemp = q"EOS
usage: promptoglyph-vcs [-t <milliseconds>]

Options:

  --help, -h
    Display this help text

  --version, -v
    Display the version info

  --time-limit, -t <milliseconds>
    The maximum amount of time the program can run before exiting,
    in milliseconds. Defaults to 500 milliseconds.
    Running "git status" can take a long time for big or complex
    repositories, but since this program is for a prompt,
    we can't delay an arbitrary amount of time without annoying the user.
    If it takes longer than this amount of time to get the repo status,
    we prematurely kill "git status" and display whatever information
    was received so far. The hope is that in subsequent runs, "git status" will
    complete in time since your operating system caches recently-accessed
    files and directories.

  --no-color
    Disables colored output, which is on by default

  --prefix, -p <string>
    Text to prepend to the VCS information (if in a VCS directory)

  --untracked-text, -u <string>
    Text to display when the VCS indicates untracked files
    (if in a VCS directory)

  --modified-text, -m <string>
    Text to display when the VCS indicates files modified since the last commit
    (if in a VCS directory)

  --indexed-text, -i <string>
    Text to display when the VSC indicates files ready to commit
    (if in a VCS directory)

  --suffix, -s <string>
    Text to append to the VCS information (if in a VCS directory)

  --bash, -b
    Used to emit additional escapes needed for color sequences in Bash prompts.
    Ignored if --no-color is specified.
    Ignored on Windows.

  --zsh, -z
    Used to emit additional escapes needed for color sequences in ZSH prompts.
    Ignored if --no-color is specified.
    Ignored on Windows.

promptoglyph-vcs is designed to be part of a shell prompt.
It prints a quick, symbolic look at the status of a Git repository
if you are currently in one and nothing otherwise. Output looks like
    [master {indexedText}{modifiedText}{untrackedText}]
where "master" is the current branch, {untrackedText} indicates untracked files,
{modifiedText} indicates changed but unstaged files, and {indexedText} indicates files staged
in the index. If "git status" could not run in a timely manner to get this info
(see --time-limit above), a T is placed in front.
Future plans include additional info (like when merging),
and possibly Subversion and Mercurial support.
EOS";

const string helpString = helpStringTemp
						.replace("{indexedText}", defaultIndexedText)
						.replace("{modifiedText}", defaultModifiedText)
						.replace("{untrackedText}", defaultUntrackedText);
