class_name StoryDB
## Career story: the cast, the five district crews and the chapters that tie
## race events together. Structure follows the classic open-city career
## (crews per car family, win their leader's car and power); the plot, names
## and characters are our own. Full design notes: docs/GAME_VISION.md.
##
## A chapter lists race events (EventDB ids). Win all of them to finish the
## chapter: its outro plays, the reward is paid and the next chapter opens.
## Dialogue lines are [speaker_id, text] or [speaker_id, text, voice_id].

const CAST := {
	"destiny": {"name": "DESTINY", "title": "YOUR CONTACT", "color": Color(1.0, 0.25, 0.65), "phone": true},
	"barrett": {"name": "BARRETT", "title": "MECHANIC", "color": Color(1.0, 0.62, 0.1)},
	"knox": {"name": "KNOX", "title": "RACE STARTER", "color": Color(0.85, 0.88, 0.95)},
	"juno": {"name": "DJ JUNO", "title": "NIGHT RIDE FM 99.1", "color": Color(0.55, 0.4, 1.0)},
	"viper": {"name": "VIPER", "title": "THE NIGHT CLUB", "color": Color(0.35, 1.0, 0.25)},
	"midas": {"name": "MIDAS", "title": "BOSS OF THE NIGHT CLUB", "color": Color(1.0, 0.8, 0.2)},
	"koji": {"name": "KOJI", "title": "LEADER, NEON RONIN", "color": Color(0.1, 0.85, 1.0)},
	"luxe": {"name": "LUXE", "title": "LEADER, COASTLINE KINGS", "color": Color(0.9, 0.9, 1.0)},
	"brick": {"name": "BRICK", "title": "LEADER, WAREHOUSE WOLVES", "color": Color(1.0, 0.3, 0.15)},
	"torque": {"name": "TORQUE", "title": "LEADER, DUNE TITANS", "color": Color(0.95, 0.7, 0.4)},
	"nova": {"name": "NOVA", "title": "LEADER, MARINA ROYALE", "color": Color(0.75, 0.3, 1.0)},
	"reward": {"name": "REWARD", "title": "", "color": Color(0.35, 1.0, 0.35)},
}

const CREWS := {
	"ronin": {"name": "NEON RONIN", "district": "DOWNTOWN", "family": "JAPANESE TUNERS", "leader": "koji", "color": Color(0.1, 0.85, 1.0)},
	"kings": {"name": "COASTLINE KINGS", "district": "JUMEIRAH", "family": "LUXURY SEDANS", "leader": "luxe", "color": Color(0.9, 0.9, 1.0)},
	"wolves": {"name": "WAREHOUSE WOLVES", "district": "AL QUOZ", "family": "AMERICAN MUSCLE", "leader": "brick", "color": Color(1.0, 0.3, 0.15)},
	"titans": {"name": "DUNE TITANS", "district": "SHEIKH ZAYED ROAD", "family": "SUVS AND TRUCKS", "leader": "torque", "color": Color(0.95, 0.7, 0.4)},
	"royale": {"name": "MARINA ROYALE", "district": "DUBAI MARINA", "family": "EUROPEAN EXOTICS", "leader": "nova", "color": Color(0.75, 0.3, 1.0)},
	"club": {"name": "THE NIGHT CLUB", "district": "THE WHOLE CITY", "family": "THE BEST OF EVERYTHING", "leader": "midas", "color": Color(1.0, 0.8, 0.2)},
}

## Special abilities won from crews (one per car family).
const ABILITIES := {
	"focus": {"name": "FOCUS", "desc": "Time slows down for a few seconds so you can thread through traffic.", "color": Color(0.2, 0.75, 1.0)},
	"ram": {"name": "RAM", "desc": "Plough through traffic without losing speed.", "color": Color(1.0, 0.55, 0.1)},
	"roar": {"name": "ROAR", "desc": "A shockwave that blasts the traffic in front of you out of the way.", "color": Color(1.0, 0.25, 0.2)},
}
const FAMILY_ABILITY := {
	"tuner": "focus", "rotary": "focus", "euro": "focus", "exotic": "focus",
	"muscle": "roar", "classic": "roar",
	"sedan": "ram", "suv": "ram",
}

const CHAPTERS := [
	{
		"id": "prologue", "title": "WELCOME TO DUBAI", "sub": "PROLOGUE", "crew": "", "district": "DOWNTOWN",
		"missions": ["midnight_loop"],
		"intro": [
			["juno", "You're locked to Night Ride FM, ninety-nine point one. Midnight in Dubai, and the streets are wide awake."],
			["destiny", "So you made it. Nice ride. Barrett says you can sleep in his garage until you're paid up."],
			["destiny", "Five crews run this city after dark. Above them sits the Night Club. Nobody gets an invite without a name."],
			["destiny", "Nobody knows your name yet. Let's fix that. There's a run downtown tonight. Follow the beam."],
		],
		"outro": [
			["knox", "Winner! Not bad for a first night."],
			["viper", "Cute. A rental-spec coupe winning the kids' race."],
			["viper", "I'm Viper. Remember it, because the Night Club doesn't remember losers. Come find me when you're somebody."],
			["destiny", "Ignore him. Actually, don't. Beat every crew in this city and he'll have no choice but to race you."],
			["destiny", "Start with the Neon Ronin downtown. Tuners, like you. Their leader Koji respects speed and nothing else."],
		],
		"reward": {"money": 3000},
	},
	{
		"id": "ronin", "title": "NEON RONIN", "sub": "CHAPTER 1", "crew": "ronin", "district": "DOWNTOWN",
		"missions": ["downtown_circuit", "ronin_run", "koji_callout"],
		"intro": [
			["koji", "You're the one who won the loop. Lucky night, or are you actually fast?"],
			["koji", "Run with my crew. Win our circuit and the Ronin Run, and I'll race you myself."],
			["barrett", "Bring the car back in one piece. And spend some of that cash on parts, kid."],
		],
		"outro": [
			["koji", "Clean lines, no fear. You earned this."],
			["koji", "Ronin drivers have a trick: when it gets tight, you slow the world down. We call it Focus."],
			["reward", "ABILITY UNLOCKED: FOCUS. Fill the meter with near misses, drafting and drifts, then hit the FOCUS button in any tuner or exotic."],
			["destiny", "Word travels fast. The Coastline Kings in Jumeirah want a look at you."],
		],
		"reward": {"money": 6000, "ability": "focus"},
	},
	{
		"id": "kings", "title": "COASTLINE KINGS", "sub": "CHAPTER 2", "crew": "kings", "district": "JUMEIRAH",
		"missions": ["palm_duel", "beach_sprint", "luxe_callout"],
		"intro": [
			["luxe", "Darling, this is Jumeirah. We don't race, we arrive. Try to keep up."],
			["destiny", "The Kings drive big luxury sedans and don't brake for anybody. Watch the narrow streets."],
		],
		"outro": [
			["luxe", "Hm. You drive like you mean it. Take the Vanta. It suits a winner."],
			["reward", "CAR WON: VANTA S6. ABILITY UNLOCKED: RAM. Sedans and SUVs can now smash through traffic without slowing."],
			["juno", "Big news on the streets tonight: the new kid just took the Coastline Kings. Somebody tell Al Quoz."],
		],
		"reward": {"money": 8000, "car": "sedan", "ability": "ram"},
	},
	{
		"id": "wolves", "title": "WAREHOUSE WOLVES", "sub": "CHAPTER 3", "crew": "wolves", "district": "AL QUOZ",
		"missions": ["ironworks_dash", "container_yard", "brick_callout"],
		"intro": [
			["brick", "Al Quoz is warehouses, trucks and big blocks. No tiny turbos here."],
			["brick", "Beat my boys through the yards and I'll show you what seven litres sounds like."],
			["barrett", "Brick's car pulls like a train in a straight line. Beat him in the corners."],
		],
		"outro": [
			["brick", "Ha! Fine. Take the Brawler. And learn to Roar."],
			["reward", "CAR WON: BRAWLER 427. ABILITY UNLOCKED: ROAR. Muscle cars blast traffic out of the way."],
			["destiny", "Three down. The Dune Titans own the big road. They don't like company."],
		],
		"reward": {"money": 10000, "car": "muscle", "ability": "roar"},
	},
	{
		"id": "titans", "title": "DUNE TITANS", "sub": "CHAPTER 4", "crew": "titans", "district": "SHEIKH ZAYED ROAD",
		"missions": ["tunnel_run", "bayshore_sprint", "torque_callout"],
		"intro": [
			["torque", "Sheikh Zayed Road is ours. Two and a half tonnes of SUV doing two hundred. You sure?"],
			["destiny", "Highway races are all about top speed. Upgrade the engine before you go."],
		],
		"outro": [
			["torque", "Respect. The Titan's yours. Don't scratch the leather."],
			["reward", "CAR WON: TITAN LX."],
			["viper", "I hear you've been busy. Marina Royale will put you back in your place."],
		],
		"reward": {"money": 14000, "car": "suv"},
	},
	{
		"id": "royale", "title": "MARINA ROYALE", "sub": "CHAPTER 5", "crew": "royale", "district": "DUBAI MARINA",
		"missions": ["ocean_circuit", "marina_dash", "nova_callout"],
		"intro": [
			["nova", "The Marina is the richest kilometre of road in the world. My crew drives the cars to match."],
			["nova", "Beat us and the Night Club will have to send you an invite. Lose and go home."],
		],
		"outro": [
			["nova", "Unbelievable. Take the Verano. You're the real thing."],
			["reward", "CAR WON: VERANO GT. YOU'VE BEEN INVITED TO THE NIGHT CLUB."],
			["midas", "So. The whole city is talking about you. Come to the Ring. Let's see if the stories are true."],
		],
		"reward": {"money": 20000, "car": "euro"},
	},
	{
		"id": "club", "title": "THE NIGHT CLUB", "sub": "FINAL CHAPTER", "crew": "club", "district": "THE WHOLE CITY",
		"missions": ["full_ring", "viper_callout", "midas_final"],
		"intro": [
			["destiny", "This is it. The Ring, then Viper, then Midas. Everything you've built comes down to tonight."],
			["viper", "Told you I'd remember your name. I'll enjoy forgetting it."],
			["barrett", "Car's as ready as it'll ever be. Go show them."],
		],
		"outro": [
			["midas", "Thirty years nobody has passed me in this city. Tonight somebody did."],
			["midas", "The Ardente is yours. So is the Night Club. Try not to get comfortable."],
			["reward", "CAR WON: ARDENTE V12. YOU RUN THE NIGHT CLUB."],
			["juno", "Night Ride FM, ninety-nine point one. Dubai has a new number one. Keep driving."],
		],
		"reward": {"money": 50000, "car": "exotic"},
	},
]


static func chapter_count() -> int:
	return CHAPTERS.size()


static func chapter(i: int) -> Dictionary:
	return CHAPTERS[clampi(i, 0, CHAPTERS.size() - 1)]


## Index of the chapter that contains this event, or -1.
static func chapter_of(event_id: String) -> int:
	for i in CHAPTERS.size():
		if CHAPTERS[i].missions.has(event_id):
			return i
	return -1


static func ability_for(car_id: String) -> String:
	return FAMILY_ABILITY.get(car_id, "focus")
