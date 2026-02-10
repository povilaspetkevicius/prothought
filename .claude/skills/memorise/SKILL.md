---
name: memorise
description: Summarize and save the current conversation thread to prothought with relevant hashtags. Use when the user asks to "memorise this thread", "save this conversation", "remember this chat", or similar requests to preserve the discussion.
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash(*/prothought*)
argument-hint: [optional custom hashtags]
---

# Memorise Thread to Prothought

When the user asks to memorise or save this conversation thread:

## Step 1: Analyze the Conversation

Review the entire conversation and identify:
- The main topic or problem being discussed
- Key decisions or solutions found
- Technologies, tools, or concepts mentioned
- The outcome or current status

## Step 2: Create a Concise Summary

Write a 1-2 sentence summary that captures:
- What was discussed
- What was accomplished or decided
- Why it matters

Keep it concise but informative - you should be able to understand it weeks later.

## Step 3: Extract Relevant Hashtags

Based on the conversation, identify 2-5 relevant hashtags such as:
- Technology/language tags: `#ruby`, `#python`, `#javascript`, `#sql`
- Project/domain tags: `#prothought`, `#work`, `#personal`, `#learning`
- Activity tags: `#bugfix`, `#feature`, `#refactor`, `#research`, `#debugging`
- Topic tags: `#database`, `#api`, `#testing`, `#deployment`

If the user provided custom hashtags in $ARGUMENTS, include those as well.

## Step 4: Save to Prothought

Execute the prothought command with the summary and hashtags:

```bash
prothought "Summary text here #hashtag1 #hashtag2 #hashtag3"
```

Make sure to:
- Properly quote the entire argument
- Include the hashtags at the end of the summary
- Use the full path to prothought if needed: `~/src/tries/2026-02-05-day-amplifier/prothought.rb`

## Step 5: Confirm

After saving, confirm to the user:
- The summary that was saved
- The hashtags that were applied
- Suggest they can view it later with `prothought summarize today` or filter by hashtag

## Example

For a conversation about adding hashtag support to prothought:

```bash
prothought "Added hashtag support to prothought: created markers table, parse hashtags on save, filter by marker in summarize/conclude commands #prothought #ruby #feature #database"
```

## Important Notes

- If prothought.rb is not in PATH, use the full path
- Always include at least 2-3 relevant hashtags
- Keep the summary under 200 characters when possible
- Escape any special characters in the summary text
