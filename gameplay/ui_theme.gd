extends RefCounted
const BG=Color("090f1e")
const PANEL=Color("131f34")
const LINE=Color("30425d")
const WHITE=Color("eef8ff")
const MINT=Color("68ffe0")
const VIOLET=Color("b89aff")
const MUTED=Color("9aacc3")
static var fonts: Dictionary={}
static var atlases: Dictionary={}
static func font(kind: String) -> Font:
	if fonts.has(kind):return fonts[kind]
	var korean: Font=load("res://assets/PerfectoUI.woff2") if ResourceLoader.exists("res://assets/PerfectoUI.woff2") else ThemeDB.fallback_font
	var base: Font=korean
	if kind=="display":
		base=load("res://assets/ui/Oxanium.ttf")
		base.fallbacks=[font("body")]
	var variation:=FontVariation.new()
	variation.base_font=base
	variation.variation_opentype={TextServerManager.get_primary_interface().name_to_tag("wght"):800.0 if kind=="headline" else 650.0 if kind=="display" else 500.0}
	fonts[kind]=variation
	return variation
static func world(index: int) -> AtlasTexture:
	if atlases.has(index):return atlases[index]
	var texture: Texture2D=load("res://assets/ui/worlds.webp")
	var atlas:=AtlasTexture.new()
	atlas.atlas=texture
	atlas.filter_clip=true
	var width:=float(texture.get_width())/3
	atlas.region=Rect2(index*width,0,width,texture.get_height())
	atlases[index]=atlas
	return atlas
