class_name ProtoMessages

## Mirror of protobuf message structures as GDScript classes.
## These define the expected data format from the server,
## based on backend/proto/slot_foxchickens.proto.


class SymbolDescription:
	var sid: int = 0   # symbol id
	var pos: int = 0   # position
	var l: int = 0     # length
	var w: int = 0     # width
	var bt: int = 0    # border type: 0=none, 1=silver, 2=gold
	var ss: int = 0    # status: 0=none, 1=disappear, 2=play mystery, 3=change to wild
	var mtp: int = 0   # multiple
	var ih: int = 0    # is hit: 0=none, 1=hit and light

	static func from_dict(data: Dictionary) -> SymbolDescription:
		var sd := SymbolDescription.new()
		sd.sid = data.get("sid", 0)
		sd.pos = data.get("pos", 0)
		sd.l = data.get("l", 0)
		sd.w = data.get("w", 0)
		sd.bt = data.get("bt", 0)
		sd.ss = data.get("ss", 0)
		sd.mtp = data.get("mtp", 0)
		sd.ih = data.get("ih", 0)
		return sd


class ScreenChange:
	var pos: int = 0       # position (col * ROW + row)
	var to_sid: int = 0    # symbol ID after change (Upgrade: upgraded symbol, Extend: WILD=91)

	static func from_dict(data: Dictionary) -> ScreenChange:
		var sc := ScreenChange.new()
		sc.pos = data.get("pos", 0)
		sc.to_sid = data.get("to_sid", 0)
		return sc


class WildEffect:
	var pos: int = 0              # wild position (col * ROW + row)
	var effect_type: String = ""  # "extend", "mtp", "upgrade", "award"
	var affected: Array = []      # affected cell positions
	var value: int = 0            # effect value (e.g., multiplier)
	var changes: Array = []       # ScreenChange array: specific screen changes

	static func from_dict(data: Dictionary) -> WildEffect:
		var we := WildEffect.new()
		we.pos = data.get("pos", 0)
		we.effect_type = data.get("effect_type", "")
		we.affected = data.get("affected", [])
		we.value = data.get("value", 0)
		we.changes = data.get("changes", [])
		return we


class MultiplierInfo:
	var pos: int = 0    # position (col * ROW + row)
	var value: int = 0  # multiplier value (2, 3, 5, etc.)

	static func from_dict(data: Dictionary) -> MultiplierInfo:
		var mi := MultiplierInfo.new()
		mi.pos = data.get("pos", 0)
		mi.value = data.get("value", 0)
		return mi


class EliminateInfo:
	var sid: int = 0       # symbol id
	var wp: Array = []     # win positions
	var ws: float = 0.0    # win score
	var bs: float = 0.0    # bet size
	var spo: float = 0.0   # symbol payout
	var awmtp: float = 0.0 # award multiple
	var wsbd1: float = 0.0 # base win
	var wsbd2: float = 0.0 # win multiplier

	static func from_dict(data: Dictionary) -> EliminateInfo:
		var ei := EliminateInfo.new()
		ei.sid = data.get("sid", 0)
		ei.wp = data.get("wp", [])
		ei.ws = data.get("ws", 0.0)
		ei.bs = data.get("bs", 0.0)
		ei.spo = data.get("spo", 0.0)
		ei.awmtp = data.get("awmtp", 0.0)
		ei.wsbd1 = data.get("wsbd1", 0.0)
		ei.wsbd2 = data.get("wsbd2", 0.0)
		return ei


class ScatterInfo:
	var sid: int = 0       # symbol id
	var wp: Array = []     # win positions
	var ws: float = 0.0    # win score
	var bs: float = 0.0    # bet size
	var bl: float = 0.0    # bet level
	var spo: float = 0.0   # symbol payout

	static func from_dict(data: Dictionary) -> ScatterInfo:
		var si := ScatterInfo.new()
		si.sid = data.get("sid", 0)
		si.wp = data.get("wp", [])
		si.ws = data.get("ws", 0.0)
		si.bs = data.get("bs", 0.0)
		si.bl = data.get("bl", 0.0)
		si.spo = data.get("spo", 0.0)
		return si


class FreeGameInfo:
	var tws: float = 0.0  # total win score
	var ar: int = 0        # add round
	var lr: int = 0        # left round
	var tr: int = 0        # total round
	var rtssid: int = 0    # retrigger scatter symbol id
	var lrb: int = 0       # left round before
	var trb: int = 0       # total round before

	static func from_dict(data: Dictionary) -> FreeGameInfo:
		var fgi := FreeGameInfo.new()
		fgi.tws = data.get("tws", 0.0)
		fgi.ar = data.get("ar", 0)
		fgi.lr = data.get("lr", 0)
		fgi.tr = data.get("tr", 0)
		fgi.rtssid = data.get("rtssid", 0)
		fgi.lrb = data.get("lrb", 0)
		fgi.trb = data.get("trb", 0)
		return fgi


class FreeGameInitialState:
	var ac: String = ""     # arena_code
	var fgsct: int = 0      # free game scatter count
	var fgct: int = 0       # free game count
	var multipliers: Array = []  # initial multiplier positions

	static func from_dict(data: Dictionary) -> FreeGameInitialState:
		var fgis := FreeGameInitialState.new()
		fgis.ac = data.get("ac", "")
		fgis.fgsct = data.get("fgsct", 0)
		fgis.fgct = data.get("fgct", 0)
		fgis.multipliers = data.get("multipliers", [])
		return fgis


class ScreenInfo:
	var screen: Array = []       # SymbolDescription array
	var scnb: Array = []         # SymbolDescription array (screen before wild effects)
	var elims: Array = []        # EliminateInfo array
	var scatter: Dictionary = {} # ScatterInfo
	var fgsp: Array = []         # free game scatter positions
	var fg: Dictionary = {}      # FreeGameInfo
	var fgis: Dictionary = {}    # FreeGameInitialState
	var sws: float = 0.0         # scatter win score
	var ws: float = 0.0          # win score
	var stws: float = 0.0        # spin total win score
	var rsct: Array = []         # reel symbol count
	var dsp: Array = []          # drop symbol positions
	var stg: int = 0             # stage of drop
	var eostg: bool = false      # end of stage?
	var stgtws: float = 0.0      # stage total win score
	var stgacc: float = 0.0      # stage score accumulate
	var bid: String = ""         # bet id
	var bta: float = 0.0         # bet amount
	var wla: float = 0.0         # win lose amount
	var bala: float = 0.0        # balance after this screen
	var wlac: float = 0.0        # win lose amount for client
	var bs: float = 0.0          # bet size
	var bscm: float = 0.0        # basic multiple
	var ac: String = ""          # arena code
	var we: Array = []           # wild effects
	var sct: int = 0             # scatter count (accumulated)
	var mpi: Array = []          # multiplier positions and values


class SpinRequest:
	var chip_index: int = 0
	var arena_code: String = "11"

	func to_dict() -> Dictionary:
		return {"chip_index": chip_index, "arena_code": arena_code}


class SpinResponse:
	var round_result_list: Array = []
	var back_to_main_game: Dictionary = {}
	var bet_amount: float = 0.0
	var pay_amount: float = 0.0
	var balance: float = 0.0

	static func from_dict(data: Dictionary) -> SpinResponse:
		var resp := SpinResponse.new()
		resp.round_result_list = data.get("round_result_list", [])
		resp.back_to_main_game = data.get("back_to_main_game", {})
		resp.bet_amount = data.get("bet_amount", 0.0)
		resp.pay_amount = data.get("pay_amount", 0.0)
		resp.balance = data.get("balance", 0.0)
		return resp


class ErrorResponse:
	## -1: bet failed (param error, insufficient balance, data error)
	## -2: server busy (single wallet no reply)
	var error_code: int = 0

	static func from_dict(data: Dictionary) -> ErrorResponse:
		var er := ErrorResponse.new()
		er.error_code = data.get("error_code", 0)
		return er


class GameBaseInfo:
	var chip_setting: String = ""
	var last_screen_info: Dictionary = {}

	static func from_dict(data: Dictionary) -> GameBaseInfo:
		var gbi := GameBaseInfo.new()
		gbi.chip_setting = data.get("chip_setting", "")
		gbi.last_screen_info = data.get("last_screen_info", {})
		return gbi
