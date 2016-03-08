import std.algorithm : canFind, filter, splitter;
import std.conv : to;
import std.datetime : Duration;
import std.exception : enforce;
import std.file : exists, isFile, dirEntries, DirEntry, readText, SpanMode;
import std.path : baseName, relativePath;
import std.process; // : A whole lotta stuff
import std.range : empty, front, back;
import std.stdio : File;
import std.string : startsWith, strip, countchars, chompPrefix, toStringz;
import std.array : split;
import std.stdio;
import std.utf : toUTF16z;

import time;
import vcs;

version (Windows) version = PathFixNeeded;
version (Cygwin) version = PathFixNeeded;

version (PathFixNeeded)
{
	import systempath : customBuildPath;
}
else
{
	import std.path : customBuildPath = buildPath;
}



// Fetches information about the Git repository,
// or returns null if we are not in one.
RepoStatus* getRepoStatus(Duration allottedTime)
{
	import std.parallelism;

	// This should give us the root directory of the Git repo
	auto rootFinder = execute(["git", "rev-parse", "--show-toplevel"]);

	immutable repoRoot = rootFinder.output.strip();
	if (rootFinder.status != 0 || repoRoot.empty)
		return null;

	RepoStatus* ret = new RepoStatus;

	ret.head = getHead(repoRoot, allottedTime);

	ret.flags = asyncGetFlags(allottedTime);

	return ret;
}


private:

/// Uses asynchronous I/O to read as much git status output as it can
/// in the given amount of time.
public // So std.parallelism can get at it
StatusFlags asyncGetFlags(Duration allottedTime)
{
	StatusFlags ret;

	// Local function for processing the output of git status.
	// See the docs for git status porcelain output
	void processPorcelainLine(string line)
	{
		if (line is null || line.length == 0) // 0 length line may happen on Windows
			return;

		// git status --porcelain spits out a two-character code
		// for each file that would show up in Git status
		// Why is this .array needed? Check odd set.back error below
		string set = line[0 .. 2];

		// Question marks indicate a file is untracked.
		if (set.canFind('?')) {
			ret.untracked = true;
		}
		else {
			// The second character indicates the working tree.
			// If it is not a blank or a question mark,
			// we have some un-indexed changes.
			if (set.back != ' ')
				ret.modified = true;

			// The first character indicates the index.
			// If it is not blank or a question mark,
			// we have some indexed changes.
			if (set.front != ' ')
				ret.indexed = true;
		}
	}


version(Windows)
{
	import core.sys.windows.windows;
	// NOTE(dkg): The wonders of the Win32 API are ... sigh. It's so ugly.
	//            I cobbled this together from some MSDN examples and stackoverflow
	//            and a lot of trial and error. So feel welcome to improve this.
	STARTUPINFO startupInfo;
	PROCESS_INFORMATION processInfo;

	HANDLE g_hChildStd_IN_Rd = NULL;
	HANDLE g_hChildStd_IN_Wr = NULL;
	HANDLE g_hChildStd_OUT_Rd = NULL;
	HANDLE g_hChildStd_OUT_Wr = NULL;
	
	// Set the bInheritHandle flag so pipe handles are inherited. 
	SECURITY_ATTRIBUTES sa; 
	sa.nLength = SECURITY_ATTRIBUTES.sizeof; 
	sa.bInheritHandle = TRUE; 
	sa.lpSecurityDescriptor = NULL; 

	auto cmdptr = toUTF16z("git status --porcelain");
	const int BUFSIZE = 4096;
	uint timeLimit = cast(uint)allottedTime.total!"msecs";

	// Create a pipe for the child process's STDOUT. 
    if (!CreatePipe(&g_hChildStd_OUT_Rd, &g_hChildStd_OUT_Wr, &sa, 0)) {
        throw new Exception("CreatePipe win32 api call failed.");
    }
    // Ensure the read handle to the pipe for STDOUT is not inherited
    if (!SetHandleInformation(g_hChildStd_OUT_Rd, HANDLE_FLAG_INHERIT, 0)) {
        throw new Exception("SetHandleInformation win32 api call failed.");
    }
	// Create a pipe for the child process's STDIN. 
	if (!CreatePipe(&g_hChildStd_IN_Rd, &g_hChildStd_IN_Wr, &sa, 0)) {
		throw new Exception("2nd CreatePipe win32 api call failed.");
	}
	// Ensure the write handle to the pipe for STDIN is not inherited. 
	if (!SetHandleInformation(g_hChildStd_IN_Wr, HANDLE_FLAG_INHERIT, 0)) {
		throw new Exception("2nd SetHandleInformation win32 api call failed.");
	}
	
	startupInfo.hStdError = g_hChildStd_OUT_Wr;
	startupInfo.hStdOutput = g_hChildStd_OUT_Wr;
	startupInfo.hStdInput = g_hChildStd_IN_Rd;
	startupInfo.dwFlags |= STARTF_USESTDHANDLES;
	startupInfo.cb = startupInfo.sizeof;
	
	if (CreateProcess(NULL, cast(wchar*)cmdptr, NULL, NULL, TRUE, 0, NULL, NULL, &startupInfo, &processInfo)) {
		int waitResult = WaitForSingleObject(processInfo.hProcess, timeLimit);
		
		// Read output from the child process's pipe for STDOUT
		// and write to the parent process's pipe for STDOUT. 
		// Stop when there is no more data. 
		string ReadFromPipe(PROCESS_INFORMATION piProcInfo) {
			DWORD dwRead; 
			char[BUFSIZE] chBuf;
			int bSuccess = false;
			string outstring = "";

			for (;;) {
				bSuccess = ReadFile(g_hChildStd_OUT_Rd, cast(void*)chBuf.ptr, BUFSIZE, &dwRead, NULL);
				
				if (!bSuccess || dwRead == 0) break; 
				
				string s = (cast(immutable(char)*)chBuf)[0..dwRead];
				outstring ~= s;

				if (dwRead < BUFSIZE) break;
			}
			dwRead = 0;
			//for (;;) { 
			//	bSuccess=ReadFile( g_hChildStd_ERR_Rd, chBuf, BUFSIZE, &dwRead, NULL);
			//	if( ! bSuccess || dwRead == 0 ) break; 

			//	string s(chBuf, dwRead);
			//	err += s;

			//} 
			return outstring;
		}
		
		if (waitResult == WAIT_TIMEOUT) {
			// terminate process
			if (!TerminateProcess(processInfo.hProcess, 1)) {
				// TODO(dkg): should we abandone ship here?
				writeln("warning: git status call process did not return in time and termination failed");
			}
		} else {
			string gitStatusResult = ReadFromPipe(processInfo);
			auto lines = gitStatusResult.split("\n");
			foreach (line; lines) {
				processPorcelainLine(line);
			}
		}

		CloseHandle(processInfo.hProcess);
		CloseHandle(processInfo.hThread);
	}

	return ret;

} else version(Posix) {

	// Currently we can only do this for Unix.
	// Windows async pipe I/O (they call it "overlapped" I/O)
	// is more... involved.
	// TODO: Either write a Windows implementation or suck it up
	//       and do things synchronously in Windows.
	import core.sys.posix.poll;

	// Light off git status while we find the HEAD
	auto pipes = pipeProcess(["git", "status", "--porcelain"], Redirect.stdout);
	// If an exception gets thrown, be sure to cleanup the process.
	scope(failure) {
		kill(pipes.pid);
		wait(pipes.pid);
	}


	// We need the actual file descriptor of the pipe so we can call poll
	immutable int fdes = core.stdc.stdio.fileno(pipes.stdout.getFP());
	enforce(fdes >= 0, "fileno failed.");

	pollfd pfd;
	pfd.fd = fdes; // The file descriptor we want to poll
	pfd.events = POLLIN; // Notify us if there is data to be read

	string nextLine;

	// As long as git status is running, keep at it.
	while (!tryWait(pipes.pid).terminated) {

		// Poll the pipe with an arbitrary 5 millisecond timeout
		enforce(poll(&pfd, 1, 5) >= 0, "poll failed");

		// If we have data to read, process a line of it.
		if (pfd.revents & POLLIN) {
			nextLine = pipes.stdout.readln();
			processPorcelainLine(nextLine);
		}
		else if (pastTime(allottedTime)) {
			import core.sys.posix.signal: SIGTERM;
			kill(pipes.pid, SIGTERM);
			break;
		}
	}

	// Process anything left over
	while (nextLine !is null) {
		nextLine = pipes.stdout.readln();
		processPorcelainLine(nextLine);
	}

	// Join the process
	wait(pipes.pid);

	return ret;

} else {
	writeln("PLATFORM NOT SUPPORTED!");
	assert(0); // trips when version is not defined
}

}

/// Gets the name of the current Git head, or a shortened SHA
/// if there is no symbolic name.
string getHead(string repoRoot, Duration allottedTime)
{
	// getHead doesn't use async I/O because it is assumed that
	// reading one-line files will take a negligible amount of time.
	// If this assumption proves false, we should revisit it.

	// NOTE(dkg): added check to allow for git submodules
	// check if the .git file/folder is actually a folder
	// if it is a file, we are in a submodule
	immutable gitFileOrFolder = customBuildPath(repoRoot, ".git");
	if (exists(gitFileOrFolder) && isFile(gitFileOrFolder)) {
		string content = gitFileOrFolder.readAndStrip();
		//Example content: gitdir: ../.git/modules/modulename
		string[] contentSplit = split(content, "/");
		if (contentSplit.length > 0) {
			return "sub: " ~ (contentSplit[$-1]);
		}
		else {
			return "<an unknown submodule>";
		}
	}
	immutable gitFolder = gitFileOrFolder;  

	//immutable headPath = customBuildPath(repoRoot, ".git", "HEAD");
	immutable headPath = customBuildPath(gitFolder, "HEAD");
	immutable headSHA = headPath.readAndStrip();

	// If we're on a branch head, .git/HEAD will look like
	// ref: refs/heads/<branch>
	if (headSHA.startsWith("ref:")) {
		if (headSHA.countchars("/") == 2)
			return headSHA.baseName;
		else
			return headSHA.chompPrefix("ref: refs/heads/");
	}

	// Otherwise let's go rummaging through the refs to find something
	immutable refsPath = customBuildPath(gitFolder, "refs");

	string ret;

	// Let's check tags next
	immutable tagsPath = customBuildPath(refsPath, "tags");
	ret = searchTagsForHead(tagsPath, headSHA);
	if (!ret.empty)
		return relativePath(ret, tagsPath);
	else if (pastTime(allottedTime))
		return headSHA[0 .. 7];

	// No need to check heads as we handled that case above.
	// Let's check remotes
	immutable remotesPath = customBuildPath(refsPath, "remotes");
	ret = searchDirectoryForHead(remotesPath, headSHA);
	if (!ret.empty)
		return relativePath(ret, remotesPath);
	else if (pastTime(allottedTime))
		return headSHA[0 .. 7];


	// We didn't find anything in remotes. Let's check packed-refs
	immutable packedRefsPath = customBuildPath(gitFolder, "packed-refs");
	if (exists(packedRefsPath)) {
		auto packedRefs = File(packedRefsPath)
			.byLine
			.filter!(l => !l.startsWith('#'))
			.filter!(l => !l.startsWith('^'));

		foreach(line; packedRefs) {
			// Each line is in the form
			// <sha> <path>
			auto tokens = splitter(line);
			auto sha = tokens.front;
			tokens.popFront();
			auto refPath = tokens.front;
			tokens.popFront();
			// Line should be empty now
			enforce(tokens.empty, "Weird Git packed-refs remnant:\n" ~ tokens.to!string);

			if (sha == headSHA)
				return refPath.baseName.idup;
			else if (pastTime(allottedTime))
				return headSHA[0 .. 7];
		}
	}

	// Still nothing. Just return a shortened version of the HEAD sha
	return headSHA[0 .. 7];
}

// Utility functions for getHead

string readAndStrip(string path)
{
	return readText(path).strip();
}

bool isRefFile(ref DirEntry de)
{
	// We are ignoring remote HEADS.
	return de.isFile &&
		de.name.baseName != "HEAD";
}

string searchDirectoryForHead(string dir, string head)
{
	bool matchesHead(ref DirEntry de)
	{
		return de.name.readAndStrip() == head;
	}
	auto matchingRemotes = dirEntries(dir, SpanMode.depth, false)
		.filter!(f => isRefFile(f) && matchesHead(f));
	if (!matchingRemotes.empty)
		return matchingRemotes.front.name;
	else
		return "";
}

string searchTagsForHead(string dir, string head)
{
	bool matchesHead(ref DirEntry de)
	{
		// Tags are a special case. They can either point
		// to the tagged commit, or to an annotated tag.
		// We will use git rev-parse to extract the commit
		// either way.
		string sha = de.name.readAndStrip();
		auto execResult = execute(["git", "rev-parse", sha ~ "^{commit}"]);
		enforce(execResult.status == 0, "git rev-parse failed");
		string pointsTo = execResult.output.strip();
		return pointsTo == head;
	}

	auto matchingRemotes = dirEntries(dir, SpanMode.depth, false)
		.filter!(f => isRefFile(f) && matchesHead(f));
	if (!matchingRemotes.empty)
		return matchingRemotes.front.name;
	else
		return "";
}
