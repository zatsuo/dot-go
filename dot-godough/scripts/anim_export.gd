class_name AnimExport
extends RefCounted
## コマ (Image の並び) を、GIF アニメと Aseprite のファイル (.aseprite) に書き出す。
## どちらも画素はそのまま (補間なし)。透明は透明のまま出す。

## GIF89a。frames = 同じ大きさの Image、delay_cs = 1 コマの長さ (1/100 秒)、scale = 拡大 (整数)。
## 色が 255 をこえたら、色の細かさを落として収める
static func save_gif(frames: Array, path: String, delay_cs: int, scale := 1) -> bool:
	if frames.is_empty():
		return false
	var w: int = frames[0].get_width() * scale
	var h: int = frames[0].get_height() * scale
	# パレット: 0 番 = 透明
	var datas := []
	for f in frames:
		var im: Image = f
		if im.get_format() != Image.FORMAT_RGBA8:
			im = im.duplicate()
			im.convert(Image.FORMAT_RGBA8)
		datas.append(im.get_data())
	var shift := 0
	var index := {}
	var pal := []
	while true:
		index = {}
		pal = [Color(0, 0, 0)]
		var over := false
		for d in datas:
			for i in range(0, d.size(), 4):
				if d[i + 3] < 128:
					continue
				var k: int = ((d[i] >> shift) << 16) | ((d[i + 1] >> shift) << 8) | (d[i + 2] >> shift)
				if not index.has(k):
					if pal.size() >= 256:
						over = true
						break
					index[k] = pal.size()
					pal.append(Color8(d[i], d[i + 1], d[i + 2]))
			if over:
				break
		if not over:
			break
		shift += 1
	var bits := 2
	while (1 << bits) < pal.size():
		bits += 1
	var out := StreamPeerBuffer.new()
	out.put_data("GIF89a".to_ascii_buffer())
	out.put_u16(w)
	out.put_u16(h)
	out.put_u8(0x80 | ((bits - 1) << 4) | (bits - 1))
	out.put_u8(0)
	out.put_u8(0)
	for i in 1 << bits:
		var c: Color = pal[i] if i < pal.size() else Color(0, 0, 0)
		out.put_u8(c.r8)
		out.put_u8(c.g8)
		out.put_u8(c.b8)
	# くり返し (NETSCAPE2.0、0 = ずっと)
	out.put_data(PackedByteArray([0x21, 0xFF, 0x0B]))
	out.put_data("NETSCAPE2.0".to_ascii_buffer())
	out.put_data(PackedByteArray([0x03, 0x01, 0x00, 0x00, 0x00]))
	var fw: int = frames[0].get_width()
	var fh: int = frames[0].get_height()
	for d in datas:
		out.put_data(PackedByteArray([0x21, 0xF9, 0x04, 0x09]))      # 前のコマを消してから描く・透明あり
		out.put_u16(maxi(delay_cs, 2))
		out.put_u8(0)
		out.put_u8(0)
		out.put_u8(0x2C)
		out.put_u16(0)
		out.put_u16(0)
		out.put_u16(w)
		out.put_u16(h)
		out.put_u8(0)
		var px := PackedByteArray()
		px.resize(w * h)
		for y in fh:
			for x in fw:
				var i := (x + fw * y) * 4
				var v := 0
				if d[i + 3] >= 128:
					v = index[((d[i] >> shift) << 16) | ((d[i + 1] >> shift) << 8) | (d[i + 2] >> shift)]
				if v != 0:
					for sy in scale:
						var o := (y * scale + sy) * w + x * scale
						for sx in scale:
							px[o + sx] = v
		out.put_u8(bits)
		var lz := _lzw(px, bits)
		var p := 0
		while p < lz.size():
			var n := mini(255, lz.size() - p)
			out.put_u8(n)
			out.put_data(lz.slice(p, p + n))
			p += n
		out.put_u8(0)
	out.put_u8(0x3B)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(out.data_array)
	f.close()
	return true


## GIF の LZW (符号は下の桁から詰める)
static func _lzw(px: PackedByteArray, mcs: int) -> PackedByteArray:
	var out := PackedByteArray()
	var acc := 0
	var nacc := 0
	var clear := 1 << mcs
	var eoi := clear + 1
	var next := eoi + 1
	var size := mcs + 1
	var dict := {}
	var codes := PackedInt32Array()     # [符号, 桁数, ...]
	codes.append(clear)
	codes.append(size)
	var prefix := int(px[0])
	for i in range(1, px.size()):
		var k := int(px[i])
		var key := (prefix << 8) | k
		if dict.has(key):
			prefix = dict[key]
			continue
		codes.append(prefix)
		codes.append(size)
		if next < 4096:
			if next >= (1 << size) and size < 12:
				size += 1
			dict[key] = next
			next += 1
		else:
			codes.append(clear)
			codes.append(size)
			dict = {}
			next = eoi + 1
			size = mcs + 1
		prefix = k
	codes.append(prefix)
	codes.append(size)
	codes.append(eoi)
	codes.append(size)
	for i in range(0, codes.size(), 2):
		acc |= codes[i] << nacc
		nacc += codes[i + 1]
		while nacc >= 8:
			out.append(acc & 255)
			acc >>= 8
			nacc -= 8
	if nacc > 0:
		out.append(acc & 255)
	return out


static func _str(b: StreamPeerBuffer, s: String) -> void:
	var u := s.to_utf8_buffer()
	b.put_u16(u.size())
	b.put_data(u)


static func _chunk(b: StreamPeerBuffer, type: int, data: PackedByteArray) -> void:
	b.put_u32(data.size() + 6)
	b.put_u16(type)
	b.put_data(data)


## Aseprite のファイル。frames = 同じ大きさの Image (RGBA)、ms = 1 コマの長さ (ミリ秒)、
## tags = [{name, from, to}] (コマの番号、0 から)。レイヤーは 1 枚
static func save_ase(frames: Array, path: String, ms, tags: Array = [], layer_name := "キャラ") -> bool:
	if frames.is_empty():
		return false
	var w: int = frames[0].get_width()
	var h: int = frames[0].get_height()
	var body := StreamPeerBuffer.new()
	for fi in frames.size():
		var chunks := StreamPeerBuffer.new()
		var count := 0
		if fi == 0:
			var lay := StreamPeerBuffer.new()
			lay.put_u16(3)               # 見える・描ける
			lay.put_u16(0)               # ふつうのレイヤー
			lay.put_u16(0)
			lay.put_u16(0)
			lay.put_u16(0)
			lay.put_u16(0)               # ふつうに重ねる
			lay.put_u8(255)
			lay.put_data(PackedByteArray([0, 0, 0]))
			_str(lay, layer_name)
			_chunk(chunks, 0x2004, lay.data_array)
			count += 1
			if not tags.is_empty():
				var tg := StreamPeerBuffer.new()
				tg.put_u16(tags.size())
				tg.put_data(PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
				for t in tags:
					tg.put_u16(int(t.from))
					tg.put_u16(int(t.to))
					tg.put_u8(0)         # 前へ
					tg.put_u16(0)
					tg.put_data(PackedByteArray([0, 0, 0, 0, 0, 0]))
					tg.put_data(PackedByteArray([0, 0, 0]))
					tg.put_u8(0)
					_str(tg, str(t.name))
				_chunk(chunks, 0x2018, tg.data_array)
				count += 1
		var im: Image = frames[fi]
		if im.get_format() != Image.FORMAT_RGBA8:
			im = im.duplicate()
			im.convert(Image.FORMAT_RGBA8)
		var cel := StreamPeerBuffer.new()
		cel.put_u16(0)                   # レイヤー 0
		cel.put_16(0)
		cel.put_16(0)
		cel.put_u8(255)
		cel.put_u16(0)                   # そのままの画素 (圧縮なし)
		cel.put_16(0)
		cel.put_data(PackedByteArray([0, 0, 0, 0, 0]))
		cel.put_u16(w)
		cel.put_u16(h)
		cel.put_data(im.get_data())
		_chunk(chunks, 0x2005, cel.data_array)
		count += 1
		body.put_u32(chunks.data_array.size() + 16)
		body.put_u16(0xF1FA)
		body.put_u16(count)
		body.put_u16(int(ms[fi]) if ms is Array else int(ms))      # ms = 数 (全部同じ) か、コマごとの配列
		body.put_data(PackedByteArray([0, 0]))
		body.put_u32(count)
		body.put_data(chunks.data_array)
	var head := StreamPeerBuffer.new()
	head.put_u32(128 + body.data_array.size())
	head.put_u16(0xA5E0)
	head.put_u16(frames.size())
	head.put_u16(w)
	head.put_u16(h)
	head.put_u16(32)
	head.put_u32(1)
	head.put_u16(int(ms[0]) if ms is Array else int(ms))
	head.put_u32(0)
	head.put_u32(0)
	head.put_u8(0)
	head.put_data(PackedByteArray([0, 0, 0]))
	head.put_u16(0)
	head.put_u8(1)
	head.put_u8(1)
	head.put_16(0)
	head.put_16(0)
	head.put_u16(0)
	head.put_u16(0)
	var pad := PackedByteArray()
	pad.resize(84)
	head.put_data(pad)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(head.data_array)
	f.store_buffer(body.data_array)
	f.close()
	return true
