import std.stdio;
import core.stdc.stdlib : exit;

/// Writes whatever you tell it and then exits the program successfully
void writeAndSucceed(S...)(S toWrite)
{
	writeln(toWrite);
	exit(0);
}

/// Writes the help text and fails.
/// If the user explicitly requests help, we'll succeed (see writeAndSucceed),
/// but if what they give us isn't valid, bail.
void writeAndFail(S...)(S helpText)
{
	stderr.writeln(helpText);
	exit(1);
}
