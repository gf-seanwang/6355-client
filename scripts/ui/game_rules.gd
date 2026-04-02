extends Panel

## Displays game rules, pay table, wild effects, scatter/respin/free game rules


func _ready() -> void:
	visible = false
	$CloseButton.pressed.connect(_on_close)
	_build_content()


func show_rules() -> void:
	visible = true


func _on_close() -> void:
	visible = false


func _build_content() -> void:
	var text := $ScrollContainer/RulesLabel as Label
	text.text = """[FOX vs CHICKENS - Game Rules]

═══ PAY TABLE ═══
Cluster Pay: 6+ adjacent same symbols win.
Grid: 6×6 (36 positions)

Symbol Payouts (per bet level):
  H1 (White Chicken)  ×6=1.5  ×8=3.0  ×10=8.0  ×12+=20.0
  H2 (Red Chicken)    ×6=1.2  ×8=2.5  ×10=6.0  ×12+=15.0
  H3 (Owl)            ×6=0.8  ×8=1.5  ×10=4.0  ×12+=10.0
  M1 (Cabbage)        ×6=0.5  ×8=1.0  ×10=2.5  ×12+=6.0
  M2 (Carrot)         ×6=0.4  ×8=0.8  ×10=2.0  ×12+=5.0
  M3 (Pumpkin)        ×6=0.3  ×8=0.6  ×10=1.5  ×12+=4.0
  M4 (Sunflower)      ×6=0.25 ×8=0.5  ×10=1.2  ×12+=3.0
  M5 (Moon)           ×6=0.15 ×8=0.3  ×10=0.8  ×12+=2.0
  M6 (Star)           ×6=0.15 ×8=0.3  ×10=0.8  ×12+=2.0

═══ WILD SYMBOL ═══
Wild (W) substitutes for all symbols except Scatter.
When Wild participates in a winning cluster, one of
4 special effects is triggered:

  • Expander: Wild expands to cover up to 4 adjacent cells
  • Multiplier: Cluster win is multiplied (x2, x3, x5, x10)
  • Upgrader: Cluster symbols upgrade to a higher-paying symbol
  • Cash Prize: Awards 0.5x, 1x, 1.5x, or 2.5x of total bet

═══ SCATTER & RESPIN ═══
  3-4 Scatter → Respin (non-scatter positions respin)
  5+ Scatter  → Free Game (3 rounds)

═══ FREE GAME ═══
  • 3 initial rounds
  • 3 multiplier positions placed on the grid (2x, 3x, 5x)
  • Clusters touching a multiplier position get boosted
  • Additional scatters can add more rounds

═══ BUY FEATURES ═══
  Buy Wild (10× bet): Guarantees 3-5 Wild symbols on next spin
  Buy Free Game (100× bet): Instantly triggers Free Game
"""
