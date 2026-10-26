# User guide

A tour of what Usual Bot does, in the order you'll meet it. Everything works the same on Mac and
iPhone unless a section says otherwise.

- [Contacts and the sidebar](#contacts-and-the-sidebar)
- [Chatting with an agent](#chatting-with-an-agent)
- [Approvals and questions](#approvals-and-questions)
- [Skills and commands](#skills-and-commands)
- [Side questions and background tasks](#side-questions-and-background-tasks)
- [Model, thinking and context](#model-thinking-and-context)
- [Dictation and voice calls](#dictation-and-voice-calls)
- [Rooms](#rooms)
- [An agent's profile: routines, skills and machine](#an-agents-profile-routines-skills-and-machine)
- [Quick message (Mac)](#quick-message-mac)
- [Offline and reconnecting](#offline-and-reconnecting)
- [Keyboard shortcuts](#keyboard-shortcuts)

## Contacts and the sidebar

Usual Bot follows Hermes [Bot Mode](https://hermes-agent.nousresearch.com/docs/user-guide/bot-mode).
Each Bot (a Hermes profile) on your gateway is a contact, with one ongoing chat: the same "Bot
Chat" the Hermes desktop app keeps for it. Bot Mode's group chats are the rooms, in the same
list. The most recent conversation is at the top.

- A Bot shows the picture you gave it in the Hermes app. Without one, it gets one of Usual Bot's
  characters.
- A ring around an avatar means the agent is working.
- **Needs you** means it's waiting for your approval or an answer.
- Search (⌘F on the Mac) filters the list by name.
- The dot at the bottom of the sidebar (top left on iPhone) shows the connection. Click it to see
  the gateway and to sign out.

On the Mac, drag the sidebar narrower and it becomes a rail of avatars.

## Chatting with an agent

Type in the message box and press Return to send (Shift-Return for a new line). Replies stream in
as the agent writes them, with Markdown, code blocks you can copy, and tables. While the agent uses
tools, one line such as "Forge edited 1 file and ran 1 command" sums them up; click it to see each
step.

- **Attachments.** Use **+**, drag and drop, or paste. On iPhone, pick from Photos, the camera or
  Files. Images up to 25 MB and other files up to 50 MB.
- **Images from the agent.** When a reply names an image (a screenshot, a chart, a generated
  picture), it shows inline. Click it for full size, to share or to save.
- **Stop and steer.** While a reply runs, the send button becomes Stop. Or just send another
  message: it steers the running turn instead of waiting for it.
- **React, reply, copy.** Hover a message on the Mac, or long-press it on iPhone. Reply quotes the
  message above the box.
- **Edit and undo.** On your last message, **Edit** puts it back in the box; send it to replace the
  exchange and get a fresh answer. **Undo** takes the last exchange back.

## Approvals and questions

When an agent wants to do something that needs your OK, such as running a command, a card appears
in the chat with what it wants to run and why:

| Button | What it does |
| --- | --- |
| **Allow once** | Runs it this time only. |
| **Allow in this chat** | Allows this kind of command for the rest of this chat. |
| **Always allow** | Adds it to the agent's permanent allow list. |
| **Deny** | Refuses; the agent is told and carries on. |

When an agent asks you a question with choices, the same kind of card shows the options; pick one
or type your own answer. Approvals also wait in the ⌥Space panel on the Mac, so you can answer
without opening the chat.

## Skills and commands

Type `/` anywhere in the message box to open a menu of the agent's skills (✦) and Hermes's commands
(⌘). Keep typing to filter, use the arrow keys to move, and Return or Tab to pick.

- **Skills** are the agent's installed skills, such as `/web-research`. Picking one adds it to your
  message; write the rest and send.
- **Commands** are Hermes's own, such as `/reasoning high`, `/status`, `/usage`, `/compress`,
  `/retry` or `/undo`. Their output shows in the chat as a small block.

Commands that only make sense in a terminal or the desktop app are left out of the menu.

## Side questions and background tasks

- **`/btw <question>`** asks about the conversation without interrupting the agent. The answer
  appears in a card above the message box; close it when you're done. It isn't added to the chat.
- **`/bg <task>`** (or `/background`) hands the task to a fresh agent that runs on its own, while
  you keep chatting. A bar above the message box shows what's running; when a task finishes, its
  result joins the chat and you get a notification if the app isn't in front. If you quit the app
  meanwhile, the result is picked up the next time you open it.

## Model, thinking and context

On the Mac they sit below the message box, on the right:

- **The model menu** switches the model for this chat only. Expensive models ask first. If the
  agent is mid-reply, the switch takes effect from your next message.
- **The thinking menu** sets how hard the model reasons (for models that can).
- **The context meter** shows how full the conversation's context window is, and turns amber past
  80%. Its menu has **Compress Conversation**, which summarises older messages to free space.

Both menus also offer **Make Default for <agent>**, which saves the choice as the agent's default
everywhere, including in the official Hermes app.

On iPhone they appear inside the message box while you type, in the row of buttons under your
text:

- **The context ring** shows how full the context is; tap it for the numbers and **Compress
  Conversation**.
- **The gauge** shows how hard the model thinks: its needle rises with the level. Tap it to open a
  slider of levels above the box, with the keyboard still up; tap or slide to a level.
- **The model name** above the slider opens **Model and thinking**, with the full model list and
  every level, each with **Make Default for <agent>**.

## Dictation and voice calls

- **Dictation.** In an empty message box, tap the mic and speak. Words appear as you talk,
  recognised on the device when it can. Tap the mic again to stop, then edit and send.
- **Voice calls.** Tap the waveform button to call the agent. It hears you, answers aloud as it
  writes, and stops when you talk over it. The conversation is saved in the chat as usual. The call
  bar above the message box has the transcript, mute, end and settings, where you pick the voice,
  speed and engine:
  - **On-device** speech uses Apple's speech recognition and voices. Free, and nothing extra leaves
    your device.
  - **GPT-Live** uses OpenAI's realtime voice through your gateway, for a more natural
    conversation. It's offered when the gateway has an OpenAI key, and OpenAI bills the minutes.

## Rooms

Rooms are group chats with several agents. Create one with **+** at the top of the sidebar, name it
and pick its members.

- A message goes to every agent in the room; `@name` talks to just one.
- Each reply shows who wrote it. Agents can hand work to each other, shown as small lines in the
  conversation.
- Type `/` for the members' skills. ⌘I (or the room's name) shows its members.

Rooms are text only on the dashboard gateway: attachments in rooms need Hermes's newer gateway.

## An agent's profile: routines, skills and machine

Click the agent's name at the top of the chat (⌘I) to open its profile beside the chat (a sheet on
iPhone).

- **Routines** are the agent's scheduled jobs. The switch pauses or resumes one. To create a
  routine, ask the agent in the chat, for example "every Monday at 9, check our dependencies".
- **Skills** lists what the agent can do, with switches to turn skills on and off.
- **Machine** shows the agent's model and provider, and the gateway's address, Hermes version,
  connection status and who you're signed in as. On the Mac, when the official Hermes app is
  installed, a button opens it for advanced settings.

## Quick message (Mac)

Press **⌥Space** anywhere to open a small panel over whatever you're doing.

- Pick the agent along the top (Tab moves to the next), type, and press Return to send. The answer
  shows in the panel.
- ⌘Return opens the full chat; Esc closes the panel.
- **Waiting on you** lists approvals from every agent, with Allow and Deny.

Usual Bot keeps running in the menu bar after you close its window, so ⌥Space keeps working. Quit
it from the menu bar item.

## Offline and reconnecting

The app caches your recent chats, so they open instantly and stay readable without a connection.
When the connection drops, it reconnects by itself and catches up on what it missed: replies that
arrived meanwhile, background results and side answers. On iPhone, the connection closes when the
app goes to the background and reopens when you come back.

If an answer couldn't be recovered (for example, the gateway restarted meanwhile), the chat says
so instead of leaving you waiting.

## Keyboard shortcuts

| Shortcut | Where | What it does |
| --- | --- | --- |
| ⌥Space | Anywhere (Mac) | Opens the quick message panel |
| ⌘F | Sidebar | Search agents and rooms |
| ↑ / ↓ | Sidebar | Move between chats |
| ⌘I | Chat or room | Show the profile or room details |
| Return | Message box | Send, or pick from the open `/` or `@` menu |
| Shift-Return | Message box | New line |
| ↑ / ↓, Tab | `/` or `@` menu | Move, pick |
| Esc | `/` or `@` menu, reply, edit | Close the menu or cancel |
| Tab | Quick message | Next agent |
| ⌘Return | Quick message | Open the full chat |
