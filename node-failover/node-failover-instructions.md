## The following are Discord threads exported from the Solana Tech Discord server. This threads discuss different strategies on how to setup validator node failover to automatically transfer the validator identity to a hot-spare node. 


### Thread link https://discord.com/channels/428295358100013066/560174212967432193/1455457699771715659
```
Monster | Retsina Software — 12/30/25, 8:09 AM
Guys — I had a pretty painful offline incident because my old HA code wasn’t behaving correctly, so I decided to rewrite it from scratch (inspired by Sol Strategies’ approach).

It’s Python, works on Ubuntu 20.04+, and removes race conditions by deterministically choosing the healthy node with the highest IP in cluster as the next active node. That also means no jitter, and failover time is predictable: about 3× your poll interval.

Forks and PRs are welcome 🙏
https://github.com/monster2048/validator-ha


mexistaker — 12/30/25, 12:20 PM
Neat-o. BTW the jitter in the original source is zero when there is only one passive validator to choose from - rhttps://github.com/SOL-Strategies/solana-validator-ha/blob/master/internal/ha/manager.go#L613  . Also not sure I spot the main difference to the original - asking only to understand if there's scope for improving things in the source 👍 


Matthias | Staking Facilities — 12/30/25, 6:36 PM
Im working on this at the moment. The hot spare side of the client is finished and tested. It’s just missing that it detects if the node is active or not and then does the set identity with a unstaked keypair on the active node (or kills the client if that did not worked) if the threshold is reached.
I wanted to avoid a huge script for the user to make it as simple as possible. Even alerting is built in. Appreciate any thoughts 

https://github.com/schmiatz/solana-validator-automatic-failover 


mexistaker — 12/30/25, 11:28 PM
nice one. I had thought of making the delinquent threshold on x slots behind configurable. Not sure why I didn't in the end. Might work that in. Neat add-on for alerting. We wanted to make it as general as possible so our alerting is just a call to scripts for PD, slack, TG etc, but good to see that worked into yours too. Good to see forks and mods on it keeping everyone 🆙  👍 , thanks guys.



John | Trillium — 12/31/25, 3:01 PM
Granted, I have not read the entire source.  How does the standby kill the primary when the primary falls behind --max-vote-latency?


Matthias | Staking Facilities — 12/31/25, 3:48 PM
it kills it is maybe not 100% right wording, its more that the already active node commits suicide when it detects there is the same identity coming online 😄 
so always the already online node will crash instantly when it detects there is the same identity coming online through gossip.

the only edge case that came in my mind, that is not covered with just running this client on the failover node is, when the main node is having temporarely network issues and then comes back online later, because it would make the now active hot spare committing sucide again.
thats the missing part i mentioned above


John | Trillium — 12/31/25, 3:50 PM
Ah yes.  I have seen where both "commit suicide" at the same time as well.


Matthias | Staking Facilities — 12/31/25, 3:51 PM
with both you mean you have hot spare node and a main node running, you do set identity on the spare to switch to the same identity that is active on the main node and both crash?
never seen this and ive tested this easily 1000 times over the last weeks 😄


John | Trillium — 12/31/25, 3:52 PM
Yes - but this was on v1 or v2 of Solana client.  Probably fixed in newer versions of Agave.


Matthias | Staking Facilities — 12/31/25, 3:53 PM
here you can even see how fast the node commits suicide
https://imgur.com/a/w1CZ0VT
on the right the set identity was executed and the left one does harakiri instantly. the nodes where in different DCs


Matthias | Staking Facilities — 12/31/25, 3:53 PM
ah yeah thats absolutely possible 🙂


! ganyu | Hanabi Staking+Bribe

 — 12/31/25, 3:53 PM
why can't the lagging node demote itself/be demoted before the healthy node is promoted?
that's what my automatic failover does, self demotion happens when the node's connectivity tests fail


Matthias | Staking Facilities — 12/31/25, 3:54 PM
it can, will push that missing part latest on friday to the repo 👍 mainly to prevent the above mentioned edge case


! ganyu | Hanabi Staking+Bribe — 12/31/25, 3:57 PM
mine exposes a set of APIs gated by mTLS and uses a server external to both nodes to poll the APIs fairly frequently and proactively execute the failover procedure (demote->download/upload tower->promote), the API server executes the self demotion logic above, which will definitely cause a "no primary found" error on the external and a healthy node to be promoted
wonder if I should just make the repo public even though it's mostly spaghetti and pretty trivial to implement


Matthias | Staking Facilities — 12/31/25, 4:02 PM
sounds good 👍 i just wanted to avoid to rely on any other machine than the validator itself. also thought about sending a heartbeat from one validator to another or such, but thats just more things that can break.
but yeah please make the repo public, curious to see other implementations 🙂


! ganyu | Hanabi Staking+Bribe — 12/31/25, 4:02 PM
I deliberately avoided the option to have the monitoring service on one of the nodes since what if a cable gets cut
November 2023. Latitude. Never forgets.
https://github.com/FixedLocally/solvalmon
testing was mostly done manually including using a stub fdctl that calls the real fdctl after a 15s delay


Matthias | Staking Facilities — 12/31/25, 4:06 PM
yeah i think in the end, the "best" solution depends on the infra you run your stuff on
thanks for sharing


Xyphus — 12/31/25, 5:26 PM
There is still cases where both crashes. See https://github.com/anza-xyz/agave/issues/8752#issuecomment-3603131731 


Monster | Retsina Software — 12/31/25, 10:03 PM
I didn't check all the detail of original code, the main idea borrowed from original code is use gossip to monitor nodes states and config format. each node only mind its own business. if node it's lagging or trigger any 'not healthy' check, it'll try to put itself to passive mode, if fail it'll restart the systemd, which will put it back to passive mode. any power cycle will put node back to passive as well. All nodes monitor gossip to see do we have a active node in system. if not, will goes into check 3 time sequence, if headless for 3 check. will check I'm the biggest IP in cluster or not, if I am and also I'm healthy, will switch myself to active mode. other nodes will just keep standby if not biggest IP even if system is headless and local node is healthy. If biggest IP node can not switch to active successfully, it will restart itself, this will put current node to unhealthy state for a period of time. And will give other nodes opportunity to take over.  This is not the fastest HA failover approach, but more reliable, should be fine for any unexpected incident. for any on purpose failover, better use copy tower and switch identity approach to minimize credit loss. 


Monster | Retsina Software — 12/31/25, 10:14 PM
choose python because I assume it's more popular in community, easier to read/maintain customize and there's no performance concern for 2-5 nodes scale.


mexistaker — 1/1/26, 2:31 AM
Ok cool. TBH sounds like it does exactly what the original source does 🙂 might have been vibescoded to python but not sure I follow the performance concern vs go. And yes, for planned failovers there are better tools like the original source readme mentions too 👍 


Monster | Retsina Software — 1/1/26, 2:40 AM
I mean if there's more nodes, go has better performance, use less resource. but it should be OK if only couple of nodes to monitor. Just feel like Python is easier for ppl to customize it, might be my bias though🤣
Use gossip to monitor node state is a brilliant idea, it decoupled all nodes and make handling for each node much simple and neat.👍


Matthias | Staking Facilities — 1/2/26, 7:30 PM
finished my automatic failover client
https://github.com/schmiatz/solana-validator-automatic-failover
its as easy as it gets, build the client and run on your main and hot spare like that (assuming youre fine with defaults)
# Frankendancer node
./bin/failover \
  --votepubkey XXXYYYZZZ \
  --identity-keypair /home/solana/identity.json \
  --config /home/solana/config.toml

# Agave node
./bin/failover \
  --votepubkey XXXYYYZZZ \
  --identity-keypair /home/solana/identity.json \
  --ledger /home/solana/validator-ledger

also alerting is builtin, you can either provide a pager duty key or use the webhook parameters to send an alert to slack, telegram, discord or whatever 
```

### Thread link https://discord.com/channels/428295358100013066/799332737529151498/1448177456715534337
```
cr1sp4rm1n — 12/10/25, 6:00 AM
@Michael | SOL Strategies | Laine 
Decided on here...

Regarding the HA tool,

How does the identity need to be set up in the Agave start config file?


Michael | SOL Strategies | Laine — 12/10/25, 6:17 AM
@mexistaker is the boss of that he can assist


mexistaker — 12/10/25, 6:33 AM
However you want really. We tend to make sure all validators always start as passive (junk, non voting). That way if things go sideways on your active leader (it dies, goes delinquent etc) and another node has taken over it won't try to come back and get you in the duped identities poop. With solana-validator-ha, the command to failover is simply a script that tries to set identity to passive on the (borked) leader and if it fails to do that it straight up kills the service (if it restarts it will do so as passive). For a backup the same script simply does a set-identity to the active identity and you should hopefully be back in business in a second. 

In your case it sounds like you can tweak the example script in the repo to update symlinks instead of switching files, but the gist is the same. The tool doesn't read or require anything from your validator config per se, it should work with any flavour client. Hit me up on DM if you would like a hand, or at breakpoint 🙂


cr1sp4rm1n — 12/10/25, 6:40 AM
Thank you. I will pick this up in the AM. Wish I were able to come to BP...Family life couldn't let it work this time.

But if the symlink pointed at staked identity when it shut down (like power pull), I guess I would need something to push the symlink back to non-staked at boot or in the system service file...eh, need sleep. Thanks again.


mexistaker — 12/10/25, 6:52 AM
Yeah that's right. Your failover command can simply delete or update the symlinked identity on your dead node. But safest we find for this kind of reason is to just always have them start up with a passive dentity (not symlink). That way a power pull would just get it back but passive, if that makes sense


Jarda — 12/12/25, 2:21 PM
@mexistaker Hi, regarding the HA tool switching to backup node, how safe is the remove_tower_file or what is the best strategy here please?

EDIT: https://github.com/SOL-Strategies/solana-validator-ha/blob/741a84773529bc37b5f309174e01c6f3cecba8ba/example-scripts/ha-set-role.sh#L250 
Matthias | Staking Facilities — 12/12/25, 3:44 PM
thats not really a HA tool question, and the command the line above explains it already, or?


Jarda — 12/12/25, 3:57 PM
Maybe not strictly a HA tool question, but it’s related. I did read the comment above — I just want to be sure: is it actually safe to delete the tower file from a running validator that’s supposed to become active?
Matthias | Staking Facilities — 12/12/25, 3:58 PM
yes it is 👍


mexistaker — 12/12/25, 4:32 PM
Yeah, just example script. Edit to suit your needs/setup


cr1sp4rm1n — 12/13/25, 7:23 AM
ok, i have all my scripts modified and the validators start as unstaked. All is working good using the scripts manually foremergency-activate.sh and emergency-deactivate.sh in both directions...

Now running the dry run though only the unstaked validator sees both active and passive validators in gossip....

On the active machine I get "Warn" peer not found in gossip even thought the ip address is shows for the peer is right and the IP shows up when I grep for it in solana gossip

Both machines have --private-RPC listed in start config....what else might cause the unstaked to not show to the ha tool for the primary peer? 


mexistaker — 12/13/25, 7:34 AM
Not near computer and not sure I fully grasp the setup but if able, DM me the configs and some logs/details I may be able to help when near my tools


cr1sp4rm1n — 12/13/25, 4:21 PM
Sorry for the waste of time...got it sorted here...had ufw configured diff than on the primary....


cr1sp4rm1n — 12/13/25, 8:09 PM
@mexistaker does the tool accept 2 public RPCs to test against?


mexistaker — 12/13/25, 9:17 PM
Yes. You can supply any number of rpc URLs, it'll round robin them. We run with local + public+ private. 
https://github.com/SOL-Strategies/solana-validator-ha?tab=readme-ov-file#cluster-configuration


cr1sp4rm1n — 12/15/25, 5:51 PM
So I got fully setup and did as many tests as I could without actually shutting off one validator to test HA tool...
seems thats the next logical test...what I cant quite tell...is does it switch before the vote account becomes delinquent? It appears it will switch after (in my case) 5 seconds per test and missed 3 in a row so after 15 seconds with no voter in gossip so should be much sooner than 150 slots to become delinquent by typical standards, right?
@Ronel The Pro get banned too


mexistaker — 12/15/25, 10:28 PM
that's right, that's what it says in the docs:
https://github.com/SOL-Strategies/solana-validator-ha?tab=readme-ov-file#failover-configuration
you can configure these thresholds to be lower if you wish. bear in mind that in our testing on occasion a gossip sample might give a false positive (show missing node when it is actually there) so setting too low values for poll_interval_duration and leaderless_samples_threshold may be risky. The tool is meant to get one out of the shit automatically sooner than a human would so with that lens 15s is better than minutes or longer. 


Brad | Xandeum — 12/16/25, 11:53 PM
Is there any way to adapt that tool to protect two staked validators with a cluster of three? The use case comes from an idea in mainnet channel for splitting stake into smaller validators... It would help with capex if we could justify protecting two machines with one backup. The chances of two machines going down at the same time is not probable especially if the two are purposefully kept separate.


mexistaker — 12/17/25, 12:00 AM
currently not. each node in the cluster is assumed to share the same active identity and each have a unique passive identity - only one is allowed to run the active identity at a given time. Is what you describe essentially sharing multiple active (voting) identities so that passives can assume one of those dynamically? I can think of a possible way to massage that in as an option if that's a common or even possible setup - I'll be honest, first I hear of this if so.


Brad | Xandeum — 12/17/25, 12:05 AM
I was visioning two separate voting identities either one can see the backup ...and if the backup was turned to voting then the backup would not be in gossip and so the second voting identity would not see it and would not be able to fail over to it because it would have zero available in its peer group...


mexistaker — 12/17/25, 12:11 AM
yeah so in essence each node having n >=1 active identities to choose from. It's not a setup we considered but a high-level cycle in my head tells me it should be possible (no guarantees mostly because I'm dumb). If able can you open up a github issue/feature request for it with some details? We can go from there.
I get the usecase though I think. Having 1:1 backups can get pricey


Brad | Xandeum — 12/17/25, 12:18 AM
Sure, appreciate it. My motivation is likely futuristic... Meaning other things have to change first .. But for a large stake pool or so... Maybe an institutional client... They might consider a single kyb operator running on multiple machines acceptable and then we could have stake split amongst multiple voting machines and one additional rig for emergency and planned fail overs.


mexistaker — 12/17/25, 12:20 AM
yep I get it. take a (brain) dump of it in a gh issue and we can try some things on a branch there


mexistaker — 1/5/26, 1:52 AM
v0.1.10 added failover.delinquent_slot_distance_override as config option to set the GetVoteAccounts RPC call's DelinquentSlotDistance option. Enabling the override and setting its value to 75 (~30s) appears to be ok at least on testnet. Not sure what others use.
https://github.com/SOL-Strategies/solana-validator-ha/releases/tag/v0.1.10


Brad | Xandeum — 1/11/26, 3:19 AM
we got back to updating the HA tool to v0.1.10, and set the slots down to 30 to activate failover.

Then to test... On my primary, I used set-identity to change away from staked and it started a race condition to activate both nodes...ultimately, the primary won the race and reactivated but the secondary must have already been in the process and then lost the race but got detected as duplicate and HA tool killed the backup validator...the logs show that the issue was that both validators got unlucky with short random jitters (211ms and 396ms) from the 0-3s range, so they both activated before gossip could propagate.

I decided I will extend the takeover_jitter_duration to 10 seconds to see if they get better spreads...even though this normally wouldn't be a problem because both wouldn't usually be trying to activate at the same time i suppose....

Mostly I am just trying to understand the inner nuances of how its working...and I was wondering if the takeover_jitter_duration could be made a set amount of time instead of a random selection?  Even after changing to 10s, the two times to try takeover was 197ms and 289ms on the two...so not sure if its actually working as intended... 


lu — 1/11/26, 5:55 PM
I have use case for this, too and plan on working on that later this year. happy to sync / cooperate on this if anyone is interested.


lu — 1/11/26, 5:57 PM
I did observe this as well (with pretty much default jitter settings). I a cluster of 3 nodes, I killed the primary and then both failovers went active at the same time resulting in one of them crashing.


mexistaker — 1/12/26, 12:33 AM
the guts of the failover logic is in an annotated short(ish) function here:
https://github.com/SOL-Strategies/solana-validator-ha/blob/master/internal/ha/manager.go#L271

from what you describe, by just setting your primary to passive the "peer state" ended up with having 2 candidate healthy peers (your primary and backup) really quickly. At that point it goes into an arbitrary IP-based ranking to decide who should try to become active first (lowest IP wins). At that point each peer should delay taking over by (<rank>seconds + <takeover_jitter_duration>). Arguably this should be only if rank is over 1 so that the first peer wastes no time in trying to become active, and each subsequent healthy peer wastes just a little bit more time than the previous to avoid a race. Like you say, however, most setups are with 2 validators with one actually getting knocked out so ordinarily this situation would (and has, we had this save 2 primaries over the weekend already) end up with just one peer, the backup, in the race so it'd win pretty quickly. Might start a branch with this change and test on a testnet pair to see how it goes. Can also play with (optionally) disabling the jitter entirely, so that the delay for each peer is deterministic based on rank when there are 2 or more leader candidates in the race.
and also thanks @Brad | Xandeum @lu  for giving this a whirl and reporting issues. If able, drop us a GH issue for us to take up from there. we'll fire one up for this one. 👍


cr1sp4rm1n — 1/12/26, 4:37 PM
@mexistaker dm'd you with a report
```

### Thread link https://discord.com/channels/428295358100013066/799332737529151498/1461289612415860821
```
Yura — 1/15/26, 10:23 AM
Hi everyone 👋

We’ve been working on a tool for Solana validator identity transfer and failover.

It has been running on mainnet for about 9 months in our own setup, and a few months ago we decided to adapt it and make it public.
The work is still in progress, but we’d like to share it already. The public version is currently running on testnet.

🔗 https://github.com/StakeNode777/solana-node-manager

What problem it solves
Simplifies manual validator identity transfer
Enables automatic failover in case of server issues

Key features
Instant validator identity hot-swap between servers
Automatic failover mode
Runs on a separate control server (install once, minimal config per new node)
Supports 2+ servers (e.g. 1 active + multiple backups)
Validator identity and server credentials are stored encrypted in one place
Monitoring & alerts via Telegram
Written in pure PHP with minimal dependencies to reduce supply-chain risk

Currently tested with Agave / Jito / BAM validators.

If anyone is interested, we’re happy to help with installation or setup for free and would really appreciate any feedback from the community.


aiunic — 1/15/26, 6:35 PM
What about old simple bash scripts, are they not popular anymore?


nlgripto — 1/15/26, 6:35 PM
you don't like php?


aiunic — 1/15/26, 6:36 PM
I did not say that;)


levshaRole icon, Anza — 1/15/26, 6:50 PM
There is bash there!
Image
I'm not against php, just not in my code


/dev/null | Pumpkin's Pool  — 1/15/26, 8:03 PM
I decided I wasn't going to say anything about it, but since somebody else saw it...why of all languages would you use php for this?


! ganyu | Hanabi Staking+Bribe — 1/15/26, 8:31 PM
we're missing a validator implementation in php


Yura — 1/16/26, 9:29 AM
I'm just a PHP programmer and I used the language that was most convenient for me.


Yura — 1/16/26, 9:34 AM
Bash is used here to assist with installation and running/stopping scripts.


/dev/null | Pumpkin's Pool — 1/16/26, 4:37 PM
Fair enough
```

### Thread link https://discord.com/channels/428295358100013066/689412830075551748/1446987411941883995
```
jonny | s🧭lanacompass.com — 12/6/25, 11:11 PM
not sure if ddos related or just issues at velia but their Frankfurt DC and their website seems offline, just had to switch to backup 


SEJeff — 12/6/25, 11:55 PM
We have a solana validator in a provider that appears to be under a pretty serious ddos and our validator went delinquent. Their console is down so I can't shut the node down via ipmi, killing the stonith we'd normally use in this sort of situation.

We have a failover node that we can switch the identity to, but I'm very cautious to do so as if they get the network issue resolved, we could double vote.

Is the best course of action here to just wait for access to the original node to be restored and take the L on uptime? 


SEJeff — 12/6/25, 11:55 PM
This is the one, yes. When the resolve it, I'm worried i'll have two running voting validators. Will agave figure this out and one of them kill itself, or is it going to double sign? 


SEJeff — 12/6/25, 11:58 PM
I know how to failover, we do this all the time. I'm asking if it is safe to do so knowing access will be restored. I added you btw.
@jonny | s🧭lanacompass.com when your fra velia node network is restored, are you going to doublevote until you can shut one down?
@Zantetsu | Shinobi Systems or @trent.sol or an admin please ban @Levi 💥 for spamming nonsense


jonny | s🧭lanacompass.com — 12/7/25, 12:09 AM
I hate this as it is always a major worry, but I reasoned that the failed node needs first to catch up and I have alerting on uptime too so I will race to switch id. 

Agave does check for a duplicate id and terminates, I'm just not 100% sure it's guaranteed it'll be the node that failed that terminates vs the one that is currently live and voting


SEJeff — 12/7/25, 12:10 AM
I'd also like to believe it will notice that its tower.bin is way old and sepukku if it sees that identity voting, but yeah. That's why I'm asking here


jonny | s🧭lanacompass.com — 12/7/25, 12:14 AM
I believe there is a window after which votes on a slot are invalid anyway, that should have long passed for the slots before the outage that the failed node will know about.
So ideally it should self terminate before it has caught up and attempts to vote on fresher slots..


7Layer | Overclock — 12/7/25, 12:17 AM
this is so strange
why is this happening
yall arent even in Jito's pool or any of the other vote credit competitive ones right? 
I guess some battletesting is good though
if yall see some IP's from latitude let em know btw


jonny | s🧭lanacompass.com — 12/7/25, 12:19 AM
Jitos pool isn't pure performance anymore so probably not related at all.. but I literally just got stake from them yesterday on the new delegation strategy 


7Layer | Overclock — 12/7/25, 12:19 AM
Yeah, i'm just trying to think of possible rationale's


SEJeff — 12/7/25, 12:19 AM
We have a few validators. This one is for a client and we ran it in Velia. This validator is not in any pools I'm aware of no, it is too big for sfdp.

Teraswitch survived a 6-10T ddos recently.


7Layer | Overclock — 12/7/25, 12:20 AM
jito pool competition doesn't make as much sense as it used to, but still makes more sense to me than other possible reasons? 


SEJeff — 12/7/25, 12:20 AM
Velia's fra facility is hard down and apparently their website is hosted there.
It does appear that someone is targetting solana hosting providers fairly aggressively though


7Layer | Overclock — 12/7/25, 12:20 AM
our main validator is at datapacket
and we've been getting hammered


jonny | s🧭lanacompass.com — 12/7/25, 12:20 AM
On validators app there is a Berlin and vaduz DC listed under their asn, both are down too 


7Layer | Overclock — 12/7/25, 12:20 AM
it doesnt correlate to their other infra being hit apparently
are yall running Bam


SEJeff — 12/7/25, 12:22 AM
Yeah, it does seem that someone is doing some funny business right before BP.

Not on this node, no. Standard jito fd.
We'll prob run some jitobam when it is available


SEJeff — 12/7/25, 12:50 AM
@jonny | s🧭lanacompass.com Seems like only the older one kills itself: https://github.com/anza-xyz/agave/blob/d8c1e2b9bc8448bf583c4c5383a7c94dd2efd606/gossip/src/cluster_info.rs#L2007-L2019

https://github.com/anza-xyz/agave/blob/d8c1e2b9bc8448bf583c4c5383a7c94dd2efd606/gossip/src/contact_info.rs#L497-L499

https://github.com/anza-xyz/agave/blob/d8c1e2b9bc8448bf583c4c5383a7c94dd2efd606/gossip/src/cluster_info.rs#L2310-L2325 


jonny | s🧭lanacompass.com — 12/7/25, 1:04 AM
Hmm Im on phone but can't quite see how  set identity affects the outset value though. Backup was running before primary, but set identity to validator id more recently
Maybe I need to drag myself back to desk


Matthias | Staking Facilities — 12/7/25, 1:17 AM
Yes that’s correct 👍


SEJeff — 12/7/25, 1:18 AM
I've never had a failover where the primary wasn't accessible until today, heh.


jonny | s🧭lanacompass.com — 12/7/25, 1:18 AM
sadly looks like the primary came up for air just long enough to kill the backup 
 duplicate running instances of the same validator node: CMPSSdrTnRQBiBGTyFpdCc3VMNuLWYWaSkE8Zh5z6gbd - still can't get in


SEJeff — 12/7/25, 1:18 AM
Just been lucky I guess
jonny | s🧭lanacompass.com — 12/7/25, 1:20 AM
phew just got in, yoou might get lucky now too Jeff..  aaaand its gone :pain: 


SEJeff — 12/7/25, 1:27 AM
I was able to stop the service successfully and then the connection died.


jonny | s🧭lanacompass.com — 12/7/25, 1:28 AM
yes i switched it to the unstaked identity at least too 
would be great if the dupe check also did some kind of health check instead of killing the node that isn't 20,000 slots behind


SEJeff — 12/7/25, 1:30 AM
One nice thing is that sans startup pain, modern agave syncs pretty quick if you need to load from snapshot


Bryan | Titan Analytics — 12/7/25, 1:40 AM
Bit late... But yes #1 danger in getting ddosed or losing internet on primary is when you failover, if the primary comes back online it knocks both offline.  The primary does NOT need to catch up.  I've made that mistake once.  E.g. even if it's 100k slots behind if two nodes have the same identity both will be kicked out.

We got ddosed this AM. Seems like they are hitting everyone.


Bryan | Titan Analytics — 12/7/25, 1:41 AM
I think best best here is if you can send a reboot signal to the node from console/dashboard and it reboots to a dummy identify, then you can safely fail over. 


mexistaker — 12/7/25, 3:22 AM
Might find this worth a try: https://github.com/SOL-Strategies/solana-validator-ha

If you always have your validators start with a passive (non-voting) identity and the cmd used to make passive ensures the node goes passive (kills service, reboots, goes nuclear if need be) then a ddos causing your primary to go offline/delinquent should automatically failover to a backup.

If the ddos attack is hell bent on hitting an identity not an IP then the ddos might follow you to the backup (rekt) but in case it isn't might give some breathing room or throw it off the scent for a bit


jasper9 | Valigator — 12/7/25, 11:32 AM
Sol Strategies tool seems great in my testing so far.   It uses gossip to detect liveness and will do both promote and demote as needed.


Falco — 12/7/25, 8:49 PM
Have you been using this in "production" yet? I'm keen to try it out 🙂


jasper9 | Valigator — 12/7/25, 8:50 PM
Not yet.  Will go deep on it after breakpoint for sure.


jonny | s🧭lanacompass.com — 12/8/25, 12:13 AM
I had a play today, it does seem pretty great, thanks for the recommendations 


stefiix92 | NuFi — 12/8/25, 2:43 PM
can you share? :peepopray:


Michael | SOL Strategies | Laine — 12/9/25, 3:02 AM
Just came here to point to it. We got hit by a ddos last week and have been expanding our use of the ha tool in prod as a result, and can confirm it will kill the service if it is unable to run the set identity command to ensure the old primary doesn’t stay on the primary identity


mexistaker — 12/9/25, 3:05 AM
one can use the example failover command as a starting point to adapt to one's one needs/setup:
https://github.com/SOL-Strategies/solana-validator-ha/blob/master/example-scripts/ha-set-role.sh


SobestonRole icon, Syndica — 12/9/25, 5:48 PM
We’re matching bank hashes on testnet 
Should be expanding testing to devnet and mainnet in the coming months
If you’re at breakpoint we’ll be easy to find
We’ll all be at the syndica booth


7Layer | Overclock — 12/9/25, 8:12 PM
sounds good, I'll drop by


cr1sp4rm1n — 12/10/25, 5:47 AM
Is there a preferred place to talk about the ha tool? 
I currently use something like  --identity identity.json and --authorized-voter active-staked.json in my start config file.

I use a script to change symlink from pointing active-staked.json or unstaked.json to identity.json depending on the goal.

How does the start config script need to be formatted for use with the ha tool? 

Ive never had to use failover for anything besides planned maintenance on versions...but deciding I need to get with the times...


Michael | SOL Strategies | Laine — 12/10/25, 5:51 AM
I guess our discord or validator-monitoring-tools
https://discord.gg/solstrategies
SOL Strategies
SOL Strategies
164 Online
2,111 Members
Est. Jan 2022
Official SOL Strategies Server. A publicly traded Solana infrastructure company. Bridging TradFi with the Solana ecosystem. (CSE: HODL | NASDAQ: STKE)

Go to Server
```

### Thread link https://discord.com/channels/428295358100013066/1187805174803210341/1415663670205349959
```
Carlos — 9/11/25, 1:42 PM
hey, currently trying to understand and test the node failover switch. I've been told that there's no need to use the symlink this guide references https://docs.anza.xyz/operations/guides/validator-failover (it might cause more confusion than solution, that's the reason I was told it's not necesary). But wanted to know if the tower file switch is something that must be done or not? For what I understand from the guide, it says that the tower file needs to be copied from the staked (active) validator to the unstaked (inactive) one  BEFORE the switch, and then on the inactive validator use that tower file (with --require-tower flag) on the set-identity command. Is this strictly neccesary? Also worth mentioning, currently the "active" instance is running AGAVE, and the "backup" is running FIREDANCER. (the idea is to do the switch and then change AGAVE client to firedancer, but doing this after switch in order to avoid downtime).


ferric | stakeware.xyz — 9/11/25, 3:17 PM
yep you need to copy tower and do the symlinks as mentioned in the guide for the service restart, going to fd from agave might be fine but check the ⁠firedancer-operators history cuz I do remember someone had issues switching a while back 


Carlos — 9/11/25, 3:38 PM
yeah, been checking the channel and saw someone that the switch with fdctl got stuck


/dev/null | Pumpkin's Pool — 9/11/25, 6:05 PM
There have been bugs in the past where fdctl can get stuck
I haven't seen it lately though on the newer versions. I believe that has been patched.
Hot swapping between agave-agave and FD-FD is very easy to automate. It gets a bit messy when you want to go between agave-FD or FD-agave
For the sake of simplicity, I'd recommend just using the same client (whatever client that may be) 
I mean it might be technically possible to run with different ones long term but it just sounds messy


cajamares | soltop.sh — 9/11/25, 7:19 PM
hey everyone, what could cause votes to be generated but never sent to the TPU?

my validator shows internal tower voting activity (tower-vote latest=X) and calculates vote costs in bank metrics, but the vote connection cache consistently shows successful_packets=0 and num_packets=0. 

the validator creates votes internally but they never get transmitted to the network - vote account has 0 credits and no vote transactions appear on-chain. Vote UDP connection cache shows cache hits/misses but zero packet transmission. This persists across Jito client versions (3.0.0 and 3.0.1-jito). The validator is caught up, in gossip, and other networking works fine. 


Carlos — 9/11/25, 7:47 PM
this would actually be a one time patch (and just be stopping agave, prior to "hot-swapping" to fdctl). After this gets done, agave installation would be wiped and replaced with firedancer. So that both servers have the same client and switch is natural
```



## More sources
 - https://github.com/SOL-Strategies/solana-validator-ha
 - https://github.com/SOL-Strategies/solana-validator-failover
 - https://github.com/schmiatz/solana-validator-automatic-failover
 - https://github.com/StakeNode777/solana-node-manager
 - https://docs.anza.xyz/operations/guides/validator-failover
 - https://github.com/monster2048/validator-ha
 - https://pumpkins-pool.gitbook.io/pumpkins-pool



## Instructions:
- Do not write any code just yet, I want to brainstorm/plan first
- Give higher importance to discord interventions from users: Matthias | Staking Facilities, mexistaker, 7Layer | Overclock, ferric | stakeware.xyz
- These discord chats might be outdated and not aligned with their referenced tooling github repo
- Analyze/compare these strategies and advise on the best approach for enabling the Hayek validator with unexpected and planned failover capability
- Include in the comparison aspects like where the failover tooling needs to be installed, do I need an extra server for the tooling, does it support both planned and unexpected failover, does it support switching from agave to firedancer and vice-versa. This is not an exhaustic list, please include other aspects you consider important.
