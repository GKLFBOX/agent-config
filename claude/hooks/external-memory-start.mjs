#!/usr/bin/env node

const additionalContext = [
  "Session start external-memory gate:",
  "- Before the first substantive response in a personal development session, use the external-memory-reference skill to check the current project handoff, Project note, Todo, unresolved issues, and linked Decisions/Knowledge.",
  "- Do this on startup, resume, clear, and compact unless the user's request is clearly unrelated to development/project state.",
  "- Do not load the whole Vault. Read only the files selected by the external-memory-reference skill.",
  "- If no matching Project note or handoff exists, say it is unknown and suggest creating one."
].join("\n");

process.stdout.write(JSON.stringify({
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext
  }
}));
