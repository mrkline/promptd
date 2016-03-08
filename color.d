import std.typecons : Flag;

alias UseColor = Flag!"UseColor";

enum Escapes {
	none,
	bash,
	zsh,
	cmd
}

mixin(makeColorFunction("cyan", 36));
mixin(makeColorFunction("green", 32));
mixin(makeColorFunction("yellow", 33));
mixin(makeColorFunction("red", 31));
mixin(makeColorFunction("resetColor", 39));

private:

// Getting colored chars into the cmd.exe command line window is nearly impossible. :-(
// http://superuser.com/questions/427820/how-to-change-only-the-prompt-color-of-the-windows-command-line
// Quoting:
//
// Following the prompt of @Luke I finally get the solution. Anyone who is interested in this topic please hit the two links below:
//
// Color for the PROMPT (just the PROMPT proper) in cmd.exe and PowerShell? & http://gynvael.coldwind.pl/?id=130
//
// It is "ANSI hack developped for the CMD.exe shell".
//
//
// However, it seems possible to do if the user is using Powershell instead of cmd.exe:
// http://stackoverflow.com/a/20666813/193165
// 
// TODO(dkg): cmd.exe is not really suited for this tool anyway, but Powershell is, so we
//            should see if we can add colors for powershell.
// TODO(dkg): support colors for bash, zsh, etc. in Cygwin
string makeColorFunction(string name, int code)
{
	import std.conv : to;
	return
	`
	string ` ~ name ~ `(Escapes escapes)
	{
		string ret = "\33[` ~ code.to!string ~ `m";
		final switch (escapes) {
			case Escapes.none:
				return ret;
			case Escapes.bash:
				return bashEscape(ret);
			case Escapes.zsh:
				return zshEscape(ret);
			case Escapes.cmd:
				return "";
		}
	}
	`;
}

string zshEscape(string code)
{
	return  "%{" ~ code ~ "%}";
}

string bashEscape(string code)
{
	return "\001" ~ code ~ "\002";
}
