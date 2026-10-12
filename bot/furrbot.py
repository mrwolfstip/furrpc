# furrpc discord bot helper. furrpc starts it only when the discord bot tab is on, and stops it when furrpc closes.
# it is read only: it asks furrpc on 127.0.0.1 what is going on and posts that. it never writes files,
# changes settings or runs anything it is sent. the token comes in through the environment, never as an argument.
import asyncio
import os
import sys

import aiohttp
import discord
from discord import app_commands

port = os.environ.get("FURRPC_PORT", "")
key = os.environ.get("FURRPC_KEY", "")
token = os.environ.pop("FURRPC_BOT_TOKEN", "")
appid = os.environ.get("FURRPC_BOT_APPID", "")
owner = "someone"


def say(text):
    # furrpc shows these lines in the discord bot tab. nothing secret goes here
    print("furrbot: " + text, flush=True)


async def ask(path):
    try:
        timeout = aiohttp.ClientTimeout(total=5)
        async with aiohttp.ClientSession(timeout=timeout) as s:
            async with s.get("http://127.0.0.1:" + port + path, headers={"x-furrpc-key": key}) as r:
                if r.status != 200:
                    return None
                return await r.json()
    except Exception:
        return None


def span(seconds):
    s = int(seconds)
    h, m = s // 3600, s % 3600 // 60
    if h:
        return f"{h}h {m}m"
    return f"{m}m" if m else f"{s}s"


def url(v):
    return v if isinstance(v, str) and v.startswith(("https://", "http://")) else None


class bot(discord.Client):
    async def setup_hook(self):
        try:
            await tree.sync()
        except Exception:
            say("could not register the commands")
        self.watcher = asyncio.create_task(watch())


async def watch():
    # if furrpc is gone (even after a crash) there is nothing left to serve, so close
    parent = os.getppid()
    while os.getppid() == parent:
        await asyncio.sleep(3)
    await client.close()


client = bot(intents=discord.Intents.none(), application_id=int(appid) if appid.isdigit() else None)
# This is a user-installed app, not a server-installed bot. Its commands follow the
# user into DMs, group DMs and servers where Discord permits external apps.
tree = app_commands.CommandTree(
    client,
    allowed_installs=app_commands.AppInstallationType(guild=False, user=True),
    allowed_contexts=app_commands.AppCommandContext(guild=True, dm_channel=True, private_channel=True),
)
group = app_commands.Group(name="furrpc", description="what furrpc sees on this mac")
tree.add_command(group)


@client.event
async def on_ready():
    global owner
    try:
        info = await client.application_info()
        o = info.team.owner if info.team else info.owner
        if o:
            owner = o.display_name
    except Exception:
        pass
    say("connected")


async def reply(i, e):
    await i.followup.send(embed=e)


@group.command(name="now", description="the app furrpc shows right now")
async def now(i: discord.Interaction):
    await i.response.defer()
    d = await ask("/now")
    if d is None:
        return await i.followup.send("furrpc is not answering", ephemeral=True)
    if not d.get("app"):
        return await reply(i, discord.Embed(description="nothing is being shown right now"))
    e = discord.Embed(title=f"{owner} is playing"[:250], description=f"**{d['app']}**"[:500], color=discord.Color.blurple())
    if url(d.get("image")):
        e.set_thumbnail(url=d["image"])
    await reply(i, e)


@group.command(name="tv", description="what is playing in the apple tv app")
async def tv(i: discord.Interaction):
    await i.response.defer()
    d = await ask("/tv")
    if d is None:
        return await i.followup.send("furrpc is not answering", ephemeral=True)
    if not d.get("playing"):
        return await reply(i, discord.Embed(description=str(d.get("note", "nothing is playing"))[:500]))
    lines = [f"**{d.get('show', '')}**"]
    if isinstance(d.get("season"), int) and isinstance(d.get("number"), int):
        ep = f"s{d['season']:02d} e{d['number']:02d}"
        lines.append(ep + (" · " + d["title"] if d.get("title") else ""))
    elif d.get("title"):
        lines.append(d["title"])
    e = discord.Embed(title=f"{owner} is watching"[:250], description="\n".join(lines)[:1000], color=discord.Color.blurple())
    if url(d.get("image")):
        e.set_image(url=d["image"])
    if d.get("paused"):
        e.set_footer(text="paused")
    await reply(i, e)


@group.command(name="stats", description="local usage statistics")
async def stats(i: discord.Interaction):
    await i.response.defer()
    d = await ask("/stats")
    if d is None:
        return await i.followup.send("furrpc is not answering", ephemeral=True)
    apps = d.get("apps") or []
    if not apps:
        return await reply(i, discord.Embed(description="no stats yet. they build up while furrpc tracks apps or media"))
    rows = [f"**{a['name']}** · {span(a['seconds'])} · {a['sessions']} sessions" for a in apps[:10]]
    e = discord.Embed(title=f"{owner}'s stats"[:250], description="\n".join(rows)[:3500], color=discord.Color.blurple())
    e.set_footer(text=f"{len(apps)} apps · {d.get('sessions', 0)} sessions · {span(d.get('seconds', 0))} total")
    await reply(i, e)


def main():
    if not (port.isdigit() and key and token and appid.isdigit()):
        say("missing settings")
        sys.exit(1)
    say("connecting")
    try:
        client.run(token, log_handler=None)
    except discord.LoginFailure:
        say("login failed, check the token")
        sys.exit(1)
    except Exception as e:
        say("stopped: " + type(e).__name__)
        sys.exit(1)


main()
