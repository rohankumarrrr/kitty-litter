#!/usr/bin/env python3
"""Lets an agent that isn't meant to see the screen read another thread, but only your own words.

Shades puts your words first, then a --- line and anything from the screen. A router or
frontier prompt has its <screen> and <sessions> blocks further down. Everything else in a
thread can quote the screen, so it's left out. Anything this can't make sense of comes back empty.
"""
import json
import os
import re
import sys

KEPT = ("position", "itemId", "messageId", "createdBy", "creationSource", "senderThreadId", "type", "updatedAt")
END_OF_WORDS = re.compile(r"^---[ \t]*$|<\s*(screen|sessions)\b", re.IGNORECASE | re.MULTILINE)


def own_words(text):
    found = END_OF_WORDS.search(text or "")
    return (text or "")[: found.start()].rstrip() if found else (text or "")


def filtered(result, tool_input, me):
    thread = result.get("thread") or {}
    if me and me in (thread.get("threadId"), thread.get("parentThreadId")):
        return result
    # Text from a later offset could start past the --- line.
    if tool_input.get("textOffset") or tool_input.get("itemId"):
        return {"thread": thread, "items": [], "note": "Only the start of a message in another thread can be read."}
    items = [
        {**{key: item[key] for key in KEPT if key in item}, "text": own_words(item.get("text"))}
        for item in result.get("items") or []
        if item.get("type") == "user_message" and item.get("createdBy") == "user"
    ]
    return {
        "thread": thread,
        "items": items,
        "nextPosition": result.get("nextPosition"),
        "hasMore": result.get("hasMore"),
        "note": "Filtered: only the user's own words are shown from other threads.",
    }


def main():
    event = json.load(sys.stdin)
    response = event.get("tool_response")
    # MCP results arrive as a list of content blocks, with the JSON as text.
    block = next((b for b in response if isinstance(b, dict) and b.get("type") == "text"), None) if isinstance(response, list) else None
    raw = block["text"] if block else response
    result = json.loads(raw) if isinstance(raw, str) else raw
    safe = json.dumps(filtered(result, event.get("tool_input") or {}, os.environ.get("T3CODE_THREAD_ID")))
    output = [{**block, "text": safe}] if block else safe if isinstance(raw, str) else json.loads(safe)
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "updatedMCPToolOutput": output}}))


try:
    main()
except Exception:
    empty = json.dumps({"items": [], "note": "This thread couldn't be filtered, so nothing from it is shown."})
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "updatedMCPToolOutput": [{"type": "text", "text": empty}]}}))
