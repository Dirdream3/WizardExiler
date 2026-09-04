class_name PixelArt
extends RefCounted

## 精灵贴图的**唯一入口**。
##
## ★ 现在优先加载 assets/sprites/ 下的真素材（ADR-037：Kenney Tiny Dungeon CC0 + Painterly 图标裁切）★
##   文件不存在时才退回下面的字符画 —— 字符画留着是为了 headless 测试和"素材丢了也不炸"，
##   不是给玩家看的。来源与授权见 assets/CREDITS.md。
##
## 调色板里的字符含义：
##   . 透明   k 描边(近黑)   w 骨白   g 灰   s 皮肤
##   b 深蓝袍  B 亮蓝袍   o 橙   y 黄   r 红

# 用 static var 而不是 const，因为 Color8() 是函数调用，const 里不允许
static var PALETTE: Dictionary = {
	"k": Color8(24, 20, 34),
	"w": Color8(232, 228, 214),
	"g": Color8(120, 118, 132),
	"s": Color8(226, 178, 140),
	"b": Color8(52, 74, 138),
	"B": Color8(86, 122, 190),
	"o": Color8(214, 92, 34),
	"y": Color8(250, 202, 78),
	"r": Color8(196, 48, 48),
	"p": Color8(146, 108, 240),   # 电紫（电球术外圈）
	"c": Color8(214, 238, 255),   # 惨白（电球术芯）
	"i": Color8(110, 190, 232),   # 冰蓝（冰系投射物外圈）
	"v": Color8(96, 38, 120),     # 暗紫（混沌弹外圈）
	"n": Color8(150, 230, 90),    # 病绿（混沌弹芯）—— PoE 的混沌是绿紫配色
}

## 玩家：戴尖帽的法师，16×16
const PLAYER := [
	"................",
	"......kkkk......",
	".....kbbbbk.....",
	"....kbbbbbbk....",
	"...kbbbbbbbbk...",
	"..kkkkkkkkkkkk..",
	"....kssssssk....",
	"....kskssksk....",
	"....kssssssk....",
	"..kbbBBBBBBbbk..",
	"..kbbBBBBBBbbk..",
	"..kbbBBBBBBbbk..",
	"...kbBBBBBBbk...",
	"...kbbbbbbbbk...",
	"....kkkkkkkk....",
	"................",
]

## 敌人：骷髅战士，16×16
const SKELETON := [
	"................",
	".....wwwwww.....",
	"....wwwwwwww....",
	"....wkwwwwkw....",
	"....wkwwwwkw....",
	"....wwwwwwww....",
	".....wwwwww.....",
	"......wwww......",
	"...wwwwwwwwww...",
	"...wkwwwwwwkw...",
	"...wkwwwwwwkw...",
	"....wwwwwwww....",
	"....ww....ww....",
	"....ww....ww....",
	"...www....www...",
	"................",
]

## 火球，8×8
const FIREBALL := [
	"..oooo..",
	".oyyyyo.",
	"oyywwyyo",
	"oywwwwyo",
	"oywwwwyo",
	"oyywwyyo",
	".oyyyyo.",
	"..oooo..",
]

## 电球术（Spark）的单发电球，8×8。★ 画成朝右的闪电 ★
## 因为 projectile.gd 会把它的 rotation 设成飞行方向（它一直在乱窜，
## 不朝着走向画就会看着很别扭），朝右 = 角度 0，正好对上。
const SPARK := [
	"........",
	".pp.....",
	"..pcp...",
	"...pcpp.",
	"..ppcccp",
	".pcpp...",
	"pp......",
	"........",
]


## 冰系投射物（寒冰弹 / 冰霜脉冲共用），8×8 的冰晶
const FROSTBOLT := [
	"...ii...",
	"..iBBi..",
	".iBccBi.",
	"iBccccBi",
	"iBccccBi",
	".iBccBi.",
	"..iBBi..",
	"...ii...",
]


## 混沌投射物（精髓吸取），8×8：暗紫外圈 + 病绿芯，一眼和火/冰/电分开
const CHAOS_ORB := [
	"..vvvv..",
	".vnnnnv.",
	"vnnvvnnv",
	"vnvnnvnv",
	"vnvnnvnv",
	"vnnvvnnv",
	".vnnnnv.",
	"..vvvv..",
]


## 虚空匕首的飞刀，8×8。★ 画成朝右 ★（和电球一样，projectile.gd 会把它转到飞行方向）
const KNIFE := [
	"........",
	"........",
	"kk......",
	"kggwwwww",
	"kggwwwwc",
	"kk......",
	"........",
	"........",
]


static var _cache: Dictionary = {}


static func player() -> Texture2D:
	return _asset("player", "res://assets/sprites/player.png", func(): return from_ascii(PLAYER))


static func skeleton() -> Texture2D:
	return _asset("skeleton", "res://assets/sprites/skeleton.png", func(): return from_ascii(SKELETON))


## ★ 范围特效贴图（ADR-037 补充）★ 按技能元素选：爆发用 Painterly 的爆炸 / 气浪 / 雾，
## 锥 / 光束用转成水平的 Painterly 光束，挥砍用刀光。缺文件返回 null → AreaBurst 退回画圈。
static func fx_element(tags: int) -> String:
	if tags & CombatTags.FIRE:
		return "fire"
	if tags & CombatTags.COLD:
		return "cold"
	if tags & CombatTags.LIGHTNING:
		return "lightning"
	if tags & CombatTags.CHAOS:
		return "chaos"
	return "phys"


static func fx_burst(tags: int) -> Texture2D:
	var k := fx_element(tags)
	return _asset("fx_burst_" + k, "res://assets/fx/burst_%s.png" % k, func(): return null)


static func fx_beam(tags: int) -> Texture2D:
	var k := fx_element(tags)
	return _asset("fx_beam_" + k, "res://assets/fx/beam_%s.png" % k, func(): return null)


static func fx_slash() -> Texture2D:
	return _asset("fx_slash", "res://assets/fx/slash.png", func(): return null)


## 投射物贴图的统一摆法：32 像素的能量弹缩到 16 个世界像素、线性过滤；8 像素字符画照旧
static func projectile_setup(sprite: Sprite2D, tex: Texture2D) -> void:
	sprite.texture = tex
	if tex != null and tex.get_width() > 16:
		sprite.scale = Vector2(0.5, 0.5)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	else:
		sprite.scale = Vector2.ONE
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE


## Boss（骸骨领主一系）：远古巫妖。没有素材时退回骷髅
static func boss() -> Texture2D:
	return _asset("boss", "res://assets/sprites/boss.png", func(): return skeleton())


## ★ 角色贴图的统一摆法 ★（ADR-037 补充：换成 32×32 的 Crawl 素材后角色不再是 16 像素）
## 32 像素的图按 CHAR_SCALE 缩到约 22 个世界像素高、脚底对齐节点原点、用线性过滤 ——
## 缩放后每个纹素在屏幕上约 2.8 像素，比原来 16 像素图的 4 像素细一倍还多；
## 16 像素的字符画（测试 / 素材缺失时）照旧 1:1、最近邻。
const CHAR_SCALE := 0.7
static func char_setup(sprite: Sprite2D, tex: Texture2D) -> void:
	sprite.texture = tex
	if tex != null and tex.get_width() > 16:
		sprite.scale = Vector2(CHAR_SCALE, CHAR_SCALE)
		sprite.offset = Vector2(0.0, -tex.get_height() * 0.5)   # 脚底贴地（offset 在 scale 之前）
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	else:
		sprite.scale = Vector2.ONE
		sprite.offset = Vector2(0.0, -8.0)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE


static func fireball() -> Texture2D:
	return _asset("fireball", "res://assets/sprites/proj_fire.png", func(): return from_ascii(FIREBALL))


static func spark() -> Texture2D:
	return _asset("spark", "res://assets/sprites/proj_spark.png", func(): return from_ascii(SPARK))


static func frostbolt() -> Texture2D:
	return _asset("frostbolt", "res://assets/sprites/proj_frost.png", func(): return from_ascii(FROSTBOLT))


static func chaos_orb() -> Texture2D:
	return _asset("chaos_orb", "res://assets/sprites/proj_chaos.png", func(): return from_ascii(CHAOS_ORB))


static func knife() -> Texture2D:
	return _asset("knife", "res://assets/sprites/proj_knife.png", func(): return from_ascii(KNIFE))



static func floor_tile() -> Texture2D:
	return _asset("floor", "res://assets/sprites/floor.png", func(): return _make_floor(16, 20250831))


static func shadow() -> ImageTexture:
	return _cached("shadow", func(): return _make_shadow(12, 5))


## 把字符画变成贴图。
static func from_ascii(rows: Array) -> ImageTexture:
	var h := rows.size()
	var w: int = (rows[0] as String).length()
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		var row: String = rows[y]
		for x in mini(w, row.length()):
			var c := row[x]
			if PALETTE.has(c):
				img.set_pixel(x, y, PALETTE[c])
	return ImageTexture.create_from_image(img)


static func _make_floor(size: int, seed_value: int) -> ImageTexture:
	# 地砖用随机噪点生成，比字符画更自然。固定种子保证每次运行一样
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var base := Color8(40, 38, 52)
	for y in size:
		for x in size:
			var v := rng.randf()
			var c := base
			if v > 0.94:
				c = Color8(58, 55, 72)
			elif v > 0.87:
				c = Color8(32, 30, 42)
			img.set_pixel(x, y, c)
	# 砖缝，让地面有格子感
	var seam := Color8(28, 26, 38)
	for i in size:
		img.set_pixel(i, 0, seam)
		img.set_pixel(0, i, seam)
	return ImageTexture.create_from_image(img)


static func _make_shadow(w: int, h: int) -> ImageTexture:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := (w - 1) * 0.5
	var cy := (h - 1) * 0.5
	for y in h:
		for x in w:
			var dx := (x - cx) / (w * 0.5)
			var dy := (y - cy) / (h * 0.5)
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0.3))
	return ImageTexture.create_from_image(img)


static func _cached(key: String, maker: Callable) -> Texture2D:
	if not _cache.has(key):
		_cache[key] = maker.call()
	return _cache[key]


## 真素材优先：path 存在就 load 它，否则用 fallback 造字符画。结果按 key 缓存
static func _asset(key: String, path: String, fallback: Callable) -> Texture2D:
	if not _cache.has(key):
		if ResourceLoader.exists(path, "Texture2D"):
			_cache[key] = load(path)
		else:
			_cache[key] = fallback.call()
	return _cache[key]
