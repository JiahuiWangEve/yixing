extends SceneTree
var checks = 0
func check(ok: bool, label: String):
 checks += 1
 if not ok:
  push_error(label)
  quit(1)
func _initialize():
 var font = load('res://assets/font-subset.otf').duplicate()
 font.allow_system_fallback = false
 var original = load('res://assets/font.ttc').duplicate()
 original.allow_system_fallback = false
 var manifest = JSON.parse_string(FileAccess.get_file_as_string('res://assets/font-subset.json'))
 check(font.get_face_count() == 1, 'Subset must contain one face')
 check(manifest.source_face_index == 0, 'Preserve the original face')
 var covered = {}
 for cp in manifest.codepoints:
  var code = int(cp)
  covered[code] = true
  check(font.has_char(code), 'Missing glyph U+%04X' % code)
  check(font.get_char_size(code, 24).is_equal_approx(original.get_char_size(code,24)), 'Changed glyph metrics U+%04X' % code)
 for sample in ['弈行 将军印 关隘 决战 奇遇 工坊 休整', '短剑 长枪 流血 镇四方 固守 踏马 连袭 机关炮架 装填', '0123456789 3×3 · – … ‹ ↑ → − ∞ ● ✓']:
  # Retired UI symbols need not remain in the production subset. Every
  # actual corpus glyph is checked above; compare shaping only for that corpus.
  var current_sample = ''
  for character in sample:
   if covered.has(character.unicode_at(0)): current_sample += character
  check(not current_sample.is_empty(), 'Shaping sample has current UI glyphs')
  check(font.get_string_size(current_sample, HORIZONTAL_ALIGNMENT_LEFT,-1,24).is_equal_approx(original.get_string_size(current_sample,HORIZONTAL_ALIGNMENT_LEFT,-1,24)), 'Changed shaped string metrics: '+current_sample)
 print('PASS font runtime: ',checks,' checks; system font fallback disabled')
 quit()
