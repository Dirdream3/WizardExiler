class_name PixelArt
extends RefCounted

## 程序化生成的**占位美术**。
##
## 每个精灵就是一张"字符画"：改字符就能改图，不用开画图软件。
## 以后换成真的 PNG 时，只要把 `sprite.texture` 换掉，其它代码一行都不用动 ——
## 这就是"表现和逻辑分开"的好处。
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


static var _cache: Dictionary = {}


static func player() -> ImageTexture:
	return _cached("player", func(): return from_ascii(PLAYER))


static func skeleton() -> ImageTexture:
	return _cached("skeleton", func(): return from_ascii(SKELETON))


static func fireball() -> ImageTexture:
	return _cached("fireball", func(): return from_ascii(FIREBALL))


static func spark() -> ImageTexture:
	return _cached("spark", func(): return from_ascii(SPARK))



static func floor_tile() -> ImageTexture:
	return _cached("floor", func(): return _make_floor(16, 20250831))


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


static func _cached(key: String, maker: Callable) -> ImageTexture:
	if not _cache.has(key):
		_cache[key] = maker.call()
	return _cache[key]
