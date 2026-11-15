# Setting up Telegram for "Report a bug"

**Report a bug** (the bug button in the Edge Tray on every page, and in the desktop apps' title bar), in the site and the apps, sends what went wrong to you as a Telegram message from a bot:

```text
Someone fills in Report a bug (the site's js/bug-report.js, or the apps' bug_report.dart)
  → it's sent to https://here.uwuapps.org/api/bug-report
  → the site's server (main-site/api/bug-report.js) gives it an ID, like 20261116-7K3Q
  → the bot sends it to every chat in BUG_REPORT_CHAT_ID: you, a group, a topic or a channel
  → the person is shown "Sent as report 20261116-7K3Q.", and you see the same ID in Telegram
```

The bot only sends. It runs nowhere, has no webhook and reads nothing, so there's no server to
keep up. It's free.

Until this is done, the site and the apps work fully, but Report a bug says "Bug reports can't be
sent from the app yet." and offers email (augy@augystudios.com) instead, with the words filled in.

It takes about 15 minutes, and covers these:

| What | Where it goes | Secret? |
|---|---|---|
| The bot's token, from BotFather | Vercel, as `BUG_REPORT_BOT_TOKEN` | **Yes.** Anyone with it can send as the bot, and read what's sent to it |
| The chats that get reports, as IDs | Vercel, as `BUG_REPORT_CHAT_ID` | No, but there's no reason to share them |
| Redis (optional), for limits that hold across Vercel's instances | Vercel, as `KV_REST_API_URL` and `KV_REST_API_TOKEN` | Yes |

## 1. Make the bot

Give uwuHere a bot of its own. A bot shared with something that reads its messages (a webhook,
or a script calling `getUpdates`) gets in the way of finding chat IDs in step 2.

1. In Telegram, open **@BotFather** (the one with the blue tick) and press **Start**.
2. Send `/newbot`.
3. **Name**: what reports show as coming from, e.g. `uwuHere Bug Reports`.
4. **Username**: has to end in `bot`, e.g. `uwuhere_reports_bot`. People never need to find it,
   so any free one will do.
5. BotFather answers with the token, like `123456789:AAH…`. Copy it somewhere safe for now.

> [!WARNING]
> The token is a password. Don't commit it, paste it into chats or put it anywhere but Vercel. If
> it ever leaks, see [If the token leaks](#if-the-token-leaks).

Optional, in BotFather: `/setuserpic` gives it its picture (`docs/bug-report-bot-icon-512.png`, the
app's figure with a bug in its badge where the tick would be; `docs/bug-report-bot-icon.svg` is its
source), and
`/setdescription` says what it is. Leave **Group Privacy** on (the default): the bot needs to read
nothing in a group.

## 2. Choose where reports go, and find each chat's ID

Reports can go to one chat or several at once. Each needs its ID. For each chat you want, do its
step below, then open this in your browser, with your token in place of `<token>`:

```text
https://api.telegram.org/bot<token>/getUpdates
```

Use a private window, so the token isn't kept in your history. Find `"chat":{"id": …` in the
newest update, near the bottom: that number, minus sign and all, is the chat's ID. Telegram only
keeps updates for a day, and an empty `"result":[]` means there's nothing new: do the step again
and reload.

| Where | What to do | Its ID |
|---|---|---|
| **You** (or anyone else), privately | Open the bot (search its username) and press **Start** | A positive number, e.g. `424242` |
| **A group** | Add the bot to the group, then send `/start@uwuhere_reports_bot` (its username) in it | A negative number, `-100…` for a supergroup, e.g. `-1001234567890` |
| **One topic of a group with topics** | As for a group. Then, in the topic, a message's **Copy Message Link** gives `t.me/c/1234567890/17/…`: `17` is the topic | The group's ID, a `/`, the topic: `-1001234567890/17` |
| **A channel** | Add the bot as an **admin** with **Post Messages**, then post anything in the channel. Its ID is under `"channel_post"` | `-100…`, or `@channelname` for a public channel |

Each person who should get reports privately has to press **Start** on the bot themselves:
Telegram doesn't let a bot message anyone who hasn't.

Everyone in a group or channel you add reads every report, including any contact detail people
leave in the form. Keep it to people who should see them.

## 3. Check each chat takes a message

Before putting it in Vercel, send a test to each chat from the browser (again in a private
window), with the token and the chat's ID in place:

```text
https://api.telegram.org/bot<token>/sendMessage?chat_id=<chat ID>&text=Test
```

For a topic, give the group's ID as `chat_id` and add `&message_thread_id=<topic>`. An answer
starting `{"ok":true` means it arrived. Anything else is Telegram's reason:
[If something goes wrong](#if-something-goes-wrong) says what each means.

## 4. Give the site the token and the chats (Vercel)

On <https://vercel.com>, open the **uwuhere** project > **Settings** > **Environment Variables**.
Add each with **Production** ticked, and mark each **Sensitive** (`main-site/.env.example` lists
them too):

| Key | Value |
|---|---|
| `BUG_REPORT_BOT_TOKEN` | The token from step 1 |
| `BUG_REPORT_CHAT_ID` | The IDs from step 2, split by commas, e.g. `424242,-1001234567890/17` |

Then redeploy so the function sees them: **Deployments**, the newest one's **⋯** menu,
**Redeploy**.

A report goes to every chat at once, and counts as sent if one of them took it. One that didn't is
in Vercel's logs (step 6).

## 5. Optional: hourly limits with Redis

`/api/bug-report` is public, so it's kept from being flooded. Without Redis, each of Vercel's
instances allows 2 reports a minute from one IP. With Redis, it's also 6 an hour from one IP and
60 an hour from everyone, however many instances are running.

1. In the **uwuhere** project: **Storage** > **Create Database** > **Upstash for Redis** (from
   the Marketplace). The free plan is plenty. Pick the Singapore region, beside the functions.
2. Connect it to the **uwuhere** project, for **Production**. It adds `KV_REST_API_URL` and
   `KV_REST_API_TOKEN` to its environment variables. (`UPSTASH_REDIS_REST_URL` and
   `UPSTASH_REDIS_REST_TOKEN` work as well, if that's what you have.)
3. Redeploy.

If Redis is ever down, reports still go: only the hourly limits are skipped.

## 6. Check it works

1. Open <https://here.uwuapps.org>, then the bug button in the Edge Tray, **Report a bug**.
2. Type a line (at least five characters), and **Send**. It should say
   **Sent as report 20261116-…**, and each chat should get the report, headed with that ID.
3. Or, without the form, from PowerShell:

   ```powershell
   Invoke-RestMethod -Method Post -Uri https://here.uwuapps.org/api/bug-report -ContentType application/json -Body '{"text":"Testing the bug report bot, please ignore.","platform":"web"}'
   ```

   It answers with the report's `id`.

If a chat didn't get it, open the project's **Logs** in Vercel and search for `bug-report:`. Each
chat is named by its place in `BUG_REPORT_CHAT_ID` (chat 1, chat 2 and so on), with Telegram's
reason:

```text
bug-report: chat 2: Telegram replied 403: Forbidden: bot is not a member of the channel chat
```

A line ending `sending it as plain text` means that chat wouldn't take the rich message, and got
the same report as plain text, with the pictures replying to it. Nothing needs doing for it.

To test the code without Telegram at all: `node scripts/bug-report-test.mjs` (`API_ONLY=1` skips
the browser half).

## Adding or taking away a chat later

Change `BUG_REPORT_CHAT_ID` in Vercel and redeploy. For a new chat, do steps 2 and 3 for it first.
To stop a group getting reports, take its ID out and remove the bot from the group.

## If the token leaks

1. In **@BotFather**: `/revoke`, pick the bot. The old token stops working at once, and BotFather
   gives a new one.
2. Put the new token in `BUG_REPORT_BOT_TOKEN` in Vercel, and redeploy.

The chats and their IDs stay as they are.

## If something goes wrong

| What happens | What to do |
|---|---|
| The form says "Bug reports can't be sent from the app yet." | The function answered 503: `BUG_REPORT_BOT_TOKEN` or `BUG_REPORT_CHAT_ID` is missing, Vercel wasn't redeployed after adding them, or nothing in `BUG_REPORT_CHAT_ID` reads as a chat (a `t.me/…` link or a name without its `@` doesn't). |
| The form says "Couldn't send it right now." | Every chat refused it (502). Vercel's logs say why, by chat: see the rows below. |
| `401: Unauthorized` | The token is wrong, has a space in it, or was revoked. Copy it again from BotFather (`/mybots` > the bot > **API Token**). |
| `400: Bad Request: chat not found` | The ID is wrong (check its minus sign), or the bot was never in that chat. For a person: they haven't pressed **Start**. |
| `403: Forbidden: bot can't initiate conversation with a user` | That person hasn't pressed **Start** on the bot. |
| `403: Forbidden: bot was blocked by the user` | That person blocked or stopped the bot. They unblock it and press **Start**. |
| `403: Forbidden: bot is not a member of the channel chat`, or `bot was kicked from the supergroup chat` | Add the bot back. In a channel, as an admin with **Post Messages**. |
| `400: Bad Request: not enough rights to send text messages to the chat` | In a channel, the bot isn't an admin with **Post Messages**. In a group, members' permissions don't allow sending: allow it, or make the bot an admin. |
| `400: Bad Request: group chat was upgraded to a supergroup chat` | Turning on topics (or other settings) made the group a supergroup, with a new `-100…` ID. Send `/start@<botname>` in it again, find the new ID with `getUpdates`, and replace the old one. |
| `400: Bad Request: message thread not found` | The topic's ID is wrong, or the topic was deleted. Check it with **Copy Message Link** in the topic. |
| `getUpdates` shows `"result":[]` | Nothing has happened in the last day. Do the step in section 2 again, then reload. In a group, address the bot: `/start@<botname>`, not just `/start`. |
| `getUpdates` shows `409: Conflict: can't use getUpdates method while webhook is active` | Something set a webhook on the bot. Open `https://api.telegram.org/bot<token>/deleteWebhook`, or make the bot one of its own (step 1). |
| The form says "That's a lot of reports at once." or "…this hour." | The limits in section 5, met while testing. Wait a minute (or an hour). |
| Reports arrive, but a whole-page screenshot's file doesn't | The report still counts as sent. Vercel's logs say why, as `bug-report: chat 1: whole page 1: …`. |
