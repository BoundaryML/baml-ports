// Port of goldmark util/util_cjk.go.

/// Port of the `cjkRadicalsSupplement` range table.
function is_cjk_radicals_supplement(r: int) -> bool {
    (r >= 0x2E80 && r <= 0x2EFF)
}

/// Port of the `kangxiRadicals` range table.
function is_kangxi_radicals(r: int) -> bool {
    (r >= 0x2F00 && r <= 0x2FDF)
}

/// Port of the `ideographicDescriptionCharacters` range table.
function is_ideographic_description_characters(r: int) -> bool {
    (r >= 0x2FF0 && r <= 0x2FFF)
}

/// Port of the `cjkSymbolsAndPunctuation` range table.
function is_cjk_symbols_and_punctuation(r: int) -> bool {
    (r >= 0x3000 && r <= 0x303F)
}

/// Port of the `hiragana` range table.
function is_hiragana(r: int) -> bool {
    (r >= 0x3040 && r <= 0x309F)
}

/// Port of the `katakana` range table.
function is_katakana(r: int) -> bool {
    (r >= 0x30A0 && r <= 0x30FF)
}

/// Port of the `kanbun` range table.
function is_kanbun(r: int) -> bool {
    (r >= 0x3130 && r <= 0x318F) || (r >= 0x3190 && r <= 0x319F)
}

/// Port of the `cjkStrokes` range table.
function is_cjk_strokes(r: int) -> bool {
    (r >= 0x31C0 && r <= 0x31EF)
}

/// Port of the `katakanaPhoneticExtensions` range table.
function is_katakana_phonetic_extensions(r: int) -> bool {
    (r >= 0x31F0 && r <= 0x31FF)
}

/// Port of the `cjkCompatibility` range table.
function is_cjk_compatibility(r: int) -> bool {
    (r >= 0x3300 && r <= 0x33FF)
}

/// Port of the `cjkUnifiedIdeographsExtensionA` range table.
function is_cjk_unified_ideographs_extension_a(r: int) -> bool {
    (r >= 0x3400 && r <= 0x4DBF)
}

/// Port of the `cjkUnifiedIdeographs` range table.
function is_cjk_unified_ideographs(r: int) -> bool {
    (r >= 0x4E00 && r <= 0x9FFF)
}

/// Port of the `yiSyllables` range table.
function is_yi_syllables(r: int) -> bool {
    (r >= 0xA000 && r <= 0xA48F)
}

/// Port of the `yiRadicals` range table.
function is_yi_radicals(r: int) -> bool {
    (r >= 0xA490 && r <= 0xA4CF)
}

/// Port of the `cjkCompatibilityIdeographs` range table.
function is_cjk_compatibility_ideographs(r: int) -> bool {
    (r >= 0xF900 && r <= 0xFAFF)
}

/// Port of the `verticalForms` range table.
function is_vertical_forms(r: int) -> bool {
    (r >= 0xFE10 && r <= 0xFE1F)
}

/// Port of the `cjkCompatibilityForms` range table.
function is_cjk_compatibility_forms(r: int) -> bool {
    (r >= 0xFE30 && r <= 0xFE4F)
}

/// Port of the `smallFormVariants` range table.
function is_small_form_variants(r: int) -> bool {
    (r >= 0xFE50 && r <= 0xFE6F)
}

/// Port of the `halfwidthAndFullwidthForms` range table.
function is_halfwidth_and_fullwidth_forms(r: int) -> bool {
    (r >= 0xFF00 && r <= 0xFFEF)
}

/// Port of the `kanaSupplement` range table.
function is_kana_supplement(r: int) -> bool {
    (r >= 0x1B000 && r <= 0x1B0FF)
}

/// Port of the `kanaExtendedA` range table.
function is_kana_extended_a(r: int) -> bool {
    (r >= 0x1B100 && r <= 0x1B12F)
}

/// Port of the `smallKanaExtension` range table.
function is_small_kana_extension(r: int) -> bool {
    (r >= 0x1B130 && r <= 0x1B16F)
}

/// Port of the `cjkUnifiedIdeographsExtensionB` range table.
function is_cjk_unified_ideographs_extension_b(r: int) -> bool {
    (r >= 0x20000 && r <= 0x2A6DF)
}

/// Port of the `cjkUnifiedIdeographsExtensionC` range table.
function is_cjk_unified_ideographs_extension_c(r: int) -> bool {
    (r >= 0x2A700 && r <= 0x2B73F)
}

/// Port of the `cjkUnifiedIdeographsExtensionD` range table.
function is_cjk_unified_ideographs_extension_d(r: int) -> bool {
    (r >= 0x2B740 && r <= 0x2B81F)
}

/// Port of the `cjkUnifiedIdeographsExtensionE` range table.
function is_cjk_unified_ideographs_extension_e(r: int) -> bool {
    (r >= 0x2B820 && r <= 0x2CEAF)
}

/// Port of the `cjkUnifiedIdeographsExtensionF` range table.
function is_cjk_unified_ideographs_extension_f(r: int) -> bool {
    (r >= 0x2CEB0 && r <= 0x2EBEF)
}

/// Port of the `cjkCompatibilityIdeographsSupplement` range table.
function is_cjk_compatibility_ideographs_supplement(r: int) -> bool {
    (r >= 0x2F800 && r <= 0x2FA1F)
}

/// Port of the `cjkUnifiedIdeographsExtensionG` range table.
function is_cjk_unified_ideographs_extension_g(r: int) -> bool {
    (r >= 0x30000 && r <= 0x3134F)
}

/// IsEastAsianWideRune returns true if the given rune is an east asian wide character, otherwise false.
function is_east_asian_wide_rune(r: int) -> bool {
    is_east_asian_wide_script(r) || is_cjk_symbols_and_punctuation(r)
}

/// IsSpaceDiscardingUnicodeRune returns true if the given rune is space-discarding unicode character, otherwise false.
/// See https://www.w3.org/TR/2020/WD-css-text-3-20200429/#space-discard-set
function is_space_discarding_unicode_rune(r: int) -> bool {
    is_cjk_radicals_supplement(r)
        || is_kangxi_radicals(r)
        || is_ideographic_description_characters(r)
        || is_cjk_symbols_and_punctuation(r)
        || is_hiragana(r)
        || is_katakana(r)
        || is_kanbun(r)
        || is_cjk_strokes(r)
        || is_katakana_phonetic_extensions(r)
        || is_cjk_compatibility(r)
        || is_cjk_unified_ideographs_extension_a(r)
        || is_cjk_unified_ideographs(r)
        || is_yi_syllables(r)
        || is_yi_radicals(r)
        || is_cjk_compatibility_ideographs(r)
        || is_vertical_forms(r)
        || is_cjk_compatibility_forms(r)
        || is_small_form_variants(r)
        || is_halfwidth_and_fullwidth_forms(r)
        || is_kana_supplement(r)
        || is_kana_extended_a(r)
        || is_small_kana_extension(r)
        || is_cjk_unified_ideographs_extension_b(r)
        || is_cjk_unified_ideographs_extension_c(r)
        || is_cjk_unified_ideographs_extension_d(r)
        || is_cjk_unified_ideographs_extension_e(r)
        || is_cjk_unified_ideographs_extension_f(r)
        || is_cjk_compatibility_ideographs_supplement(r)
        || is_cjk_unified_ideographs_extension_g(r)
}

/// EastAsianWidth returns the east asian width of the given rune.
/// See https://www.unicode.org/reports/tr11/tr11-36.html
function east_asian_width(r: int) -> string {
    if (r == 0x3000 ||
        (0xFF01 <= r && r <= 0xFF60) ||
        (0xFFE0 <= r && r <= 0xFFE6)) {
        "F"
    } else if (r == 0x20A9 ||
        (0xFF61 <= r && r <= 0xFFBE) ||
        (0xFFC2 <= r && r <= 0xFFC7) ||
        (0xFFCA <= r && r <= 0xFFCF) ||
        (0xFFD2 <= r && r <= 0xFFD7) ||
        (0xFFDA <= r && r <= 0xFFDC) ||
        (0xFFE8 <= r && r <= 0xFFEE)) {
        "H"
    } else if ((0x1100 <= r && r <= 0x115F) ||
        (0x11A3 <= r && r <= 0x11A7) ||
        (0x11FA <= r && r <= 0x11FF) ||
        (0x2329 <= r && r <= 0x232A) ||
        (0x2E80 <= r && r <= 0x2E99) ||
        (0x2E9B <= r && r <= 0x2EF3) ||
        (0x2F00 <= r && r <= 0x2FD5) ||
        (0x2FF0 <= r && r <= 0x2FFB) ||
        (0x3001 <= r && r <= 0x303E) ||
        (0x3041 <= r && r <= 0x3096) ||
        (0x3099 <= r && r <= 0x30FF) ||
        (0x3105 <= r && r <= 0x312D) ||
        (0x3131 <= r && r <= 0x318E) ||
        (0x3190 <= r && r <= 0x31BA) ||
        (0x31C0 <= r && r <= 0x31E3) ||
        (0x31F0 <= r && r <= 0x321E) ||
        (0x3220 <= r && r <= 0x3247) ||
        (0x3250 <= r && r <= 0x32FE) ||
        (0x3300 <= r && r <= 0x4DBF) ||
        (0x4E00 <= r && r <= 0xA48C) ||
        (0xA490 <= r && r <= 0xA4C6) ||
        (0xA960 <= r && r <= 0xA97C) ||
        (0xAC00 <= r && r <= 0xD7A3) ||
        (0xD7B0 <= r && r <= 0xD7C6) ||
        (0xD7CB <= r && r <= 0xD7FB) ||
        (0xF900 <= r && r <= 0xFAFF) ||
        (0xFE10 <= r && r <= 0xFE19) ||
        (0xFE30 <= r && r <= 0xFE52) ||
        (0xFE54 <= r && r <= 0xFE66) ||
        (0xFE68 <= r && r <= 0xFE6B) ||
        (0x1B000 <= r && r <= 0x1B001) ||
        (0x1F200 <= r && r <= 0x1F202) ||
        (0x1F210 <= r && r <= 0x1F23A) ||
        (0x1F240 <= r && r <= 0x1F248) ||
        (0x1F250 <= r && r <= 0x1F251) ||
        (0x20000 <= r && r <= 0x2F73F) ||
        (0x2B740 <= r && r <= 0x2FFFD) ||
        (0x30000 <= r && r <= 0x3FFFD)) {
        "W"
    } else if ((0x0020 <= r && r <= 0x007E) ||
        (0x00A2 <= r && r <= 0x00A3) ||
        (0x00A5 <= r && r <= 0x00A6) ||
        r == 0x00AC ||
        r == 0x00AF ||
        (0x27E6 <= r && r <= 0x27ED) ||
        (0x2985 <= r && r <= 0x2986)) {
        "Na"
    } else if ((r == 0x00A1) ||
        (r == 0x00A4) ||
        (0x00A7 <= r && r <= 0x00A8) ||
        (r == 0x00AA) ||
        (0x00AD <= r && r <= 0x00AE) ||
        (0x00B0 <= r && r <= 0x00B4) ||
        (0x00B6 <= r && r <= 0x00BA) ||
        (0x00BC <= r && r <= 0x00BF) ||
        (r == 0x00C6) ||
        (r == 0x00D0) ||
        (0x00D7 <= r && r <= 0x00D8) ||
        (0x00DE <= r && r <= 0x00E1) ||
        (r == 0x00E6) ||
        (0x00E8 <= r && r <= 0x00EA) ||
        (0x00EC <= r && r <= 0x00ED) ||
        (r == 0x00F0) ||
        (0x00F2 <= r && r <= 0x00F3) ||
        (0x00F7 <= r && r <= 0x00FA) ||
        (r == 0x00FC) ||
        (r == 0x00FE) ||
        (r == 0x0101) ||
        (r == 0x0111) ||
        (r == 0x0113) ||
        (r == 0x011B) ||
        (0x0126 <= r && r <= 0x0127) ||
        (r == 0x012B) ||
        (0x0131 <= r && r <= 0x0133) ||
        (r == 0x0138) ||
        (0x013F <= r && r <= 0x0142) ||
        (r == 0x0144) ||
        (0x0148 <= r && r <= 0x014B) ||
        (r == 0x014D) ||
        (0x0152 <= r && r <= 0x0153) ||
        (0x0166 <= r && r <= 0x0167) ||
        (r == 0x016B) ||
        (r == 0x01CE) ||
        (r == 0x01D0) ||
        (r == 0x01D2) ||
        (r == 0x01D4) ||
        (r == 0x01D6) ||
        (r == 0x01D8) ||
        (r == 0x01DA) ||
        (r == 0x01DC) ||
        (r == 0x0251) ||
        (r == 0x0261) ||
        (r == 0x02C4) ||
        (r == 0x02C7) ||
        (0x02C9 <= r && r <= 0x02CB) ||
        (r == 0x02CD) ||
        (r == 0x02D0) ||
        (0x02D8 <= r && r <= 0x02DB) ||
        (r == 0x02DD) ||
        (r == 0x02DF) ||
        (0x0300 <= r && r <= 0x036F) ||
        (0x0391 <= r && r <= 0x03A1) ||
        (0x03A3 <= r && r <= 0x03A9) ||
        (0x03B1 <= r && r <= 0x03C1) ||
        (0x03C3 <= r && r <= 0x03C9) ||
        (r == 0x0401) ||
        (0x0410 <= r && r <= 0x044F) ||
        (r == 0x0451) ||
        (r == 0x2010) ||
        (0x2013 <= r && r <= 0x2016) ||
        (0x2018 <= r && r <= 0x2019) ||
        (0x201C <= r && r <= 0x201D) ||
        (0x2020 <= r && r <= 0x2022) ||
        (0x2024 <= r && r <= 0x2027) ||
        (r == 0x2030) ||
        (0x2032 <= r && r <= 0x2033) ||
        (r == 0x2035) ||
        (r == 0x203B) ||
        (r == 0x203E) ||
        (r == 0x2074) ||
        (r == 0x207F) ||
        (0x2081 <= r && r <= 0x2084) ||
        (r == 0x20AC) ||
        (r == 0x2103) ||
        (r == 0x2105) ||
        (r == 0x2109) ||
        (r == 0x2113) ||
        (r == 0x2116) ||
        (0x2121 <= r && r <= 0x2122) ||
        (r == 0x2126) ||
        (r == 0x212B) ||
        (0x2153 <= r && r <= 0x2154) ||
        (0x215B <= r && r <= 0x215E) ||
        (0x2160 <= r && r <= 0x216B) ||
        (0x2170 <= r && r <= 0x2179) ||
        (r == 0x2189) ||
        (0x2190 <= r && r <= 0x2199) ||
        (0x21B8 <= r && r <= 0x21B9) ||
        (r == 0x21D2) ||
        (r == 0x21D4) ||
        (r == 0x21E7) ||
        (r == 0x2200) ||
        (0x2202 <= r && r <= 0x2203) ||
        (0x2207 <= r && r <= 0x2208) ||
        (r == 0x220B) ||
        (r == 0x220F) ||
        (r == 0x2211) ||
        (r == 0x2215) ||
        (r == 0x221A) ||
        (0x221D <= r && r <= 0x2220) ||
        (r == 0x2223) ||
        (r == 0x2225) ||
        (0x2227 <= r && r <= 0x222C) ||
        (r == 0x222E) ||
        (0x2234 <= r && r <= 0x2237) ||
        (0x223C <= r && r <= 0x223D) ||
        (r == 0x2248) ||
        (r == 0x224C) ||
        (r == 0x2252) ||
        (0x2260 <= r && r <= 0x2261) ||
        (0x2264 <= r && r <= 0x2267) ||
        (0x226A <= r && r <= 0x226B) ||
        (0x226E <= r && r <= 0x226F) ||
        (0x2282 <= r && r <= 0x2283) ||
        (0x2286 <= r && r <= 0x2287) ||
        (r == 0x2295) ||
        (r == 0x2299) ||
        (r == 0x22A5) ||
        (r == 0x22BF) ||
        (r == 0x2312) ||
        (0x2460 <= r && r <= 0x24E9) ||
        (0x24EB <= r && r <= 0x254B) ||
        (0x2550 <= r && r <= 0x2573) ||
        (0x2580 <= r && r <= 0x258F) ||
        (0x2592 <= r && r <= 0x2595) ||
        (0x25A0 <= r && r <= 0x25A1) ||
        (0x25A3 <= r && r <= 0x25A9) ||
        (0x25B2 <= r && r <= 0x25B3) ||
        (0x25B6 <= r && r <= 0x25B7) ||
        (0x25BC <= r && r <= 0x25BD) ||
        (0x25C0 <= r && r <= 0x25C1) ||
        (0x25C6 <= r && r <= 0x25C8) ||
        (r == 0x25CB) ||
        (0x25CE <= r && r <= 0x25D1) ||
        (0x25E2 <= r && r <= 0x25E5) ||
        (r == 0x25EF) ||
        (0x2605 <= r && r <= 0x2606) ||
        (r == 0x2609) ||
        (0x260E <= r && r <= 0x260F) ||
        (0x2614 <= r && r <= 0x2615) ||
        (r == 0x261C) ||
        (r == 0x261E) ||
        (r == 0x2640) ||
        (r == 0x2642) ||
        (0x2660 <= r && r <= 0x2661) ||
        (0x2663 <= r && r <= 0x2665) ||
        (0x2667 <= r && r <= 0x266A) ||
        (0x266C <= r && r <= 0x266D) ||
        (r == 0x266F) ||
        (0x269E <= r && r <= 0x269F) ||
        (0x26BE <= r && r <= 0x26BF) ||
        (0x26C4 <= r && r <= 0x26CD) ||
        (0x26CF <= r && r <= 0x26E1) ||
        (r == 0x26E3) ||
        (0x26E8 <= r && r <= 0x26FF) ||
        (r == 0x273D) ||
        (r == 0x2757) ||
        (0x2776 <= r && r <= 0x277F) ||
        (0x2B55 <= r && r <= 0x2B59) ||
        (0x3248 <= r && r <= 0x324F) ||
        (0xE000 <= r && r <= 0xF8FF) ||
        (0xFE00 <= r && r <= 0xFE0F) ||
        (r == 0xFFFD) ||
        (0x1F100 <= r && r <= 0x1F10A) ||
        (0x1F110 <= r && r <= 0x1F12D) ||
        (0x1F130 <= r && r <= 0x1F169) ||
        (0x1F170 <= r && r <= 0x1F19A) ||
        (0xE0100 <= r && r <= 0xE01EF) ||
        (0xF0000 <= r && r <= 0xFFFFD) ||
        (0x100000 <= r && r <= 0x10FFFD)) {
        "A"
    } else {
        "N"
    }
}
