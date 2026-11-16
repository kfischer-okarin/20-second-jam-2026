require 'tests/test_helper'

describe PixelFont do
  test 'every glyph is five pixels wide and seven high' do
    malformed = PixelFont::GLYPHS.reject { |_char, rows|
      rows.length == PixelFont::GLYPH_H && rows.all? { |row| row.length == PixelFont::GLYPH_W }
    }
    assert.empty! malformed.keys
  end

  test 'width leaves no spacing after the last character' do
    assert.equal! PixelFont.width('AB', 2), 22
  end

  test 'draws one sprite per visible character' do
    primitives = []
    PixelFont.draw(primitives, 'A B', 10, 20)
    assert.equal! primitives.map { |sprite| sprite[:x] }, [10, 22]
  end
end
