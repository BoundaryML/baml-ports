// Tests from heck-0.5.0 (`#[cfg(test)] mod tests` in each module)

testset "heck" {
    test "kebab" {
        assert.equal(to_kebab_case("CamelCase"), "camel-case");
        assert.equal(to_kebab_case("This is Human case."), "this-is-human-case");
        assert.equal(to_kebab_case("MixedUP CamelCase, with some Spaces"), "mixed-up-camel-case-with-some-spaces");
        assert.equal(to_kebab_case("mixed_up_ snake_case with some _spaces"), "mixed-up-snake-case-with-some-spaces");
        assert.equal(to_kebab_case("kebab-case"), "kebab-case");
        assert.equal(to_kebab_case("SHOUTY_SNAKE_CASE"), "shouty-snake-case");
        assert.equal(to_kebab_case("snake_case"), "snake-case");
        assert.equal(to_kebab_case("this-contains_ ALLKinds OfWord_Boundaries"), "this-contains-all-kinds-of-word-boundaries");
        assert.equal(to_kebab_case("XΣXΣ baﬄe"), "xσxς-baﬄe");
        assert.equal(to_kebab_case("XMLHttpRequest"), "xml-http-request")
    }
    test "snake" {
        assert.equal(to_snake_case("CamelCase"), "camel_case");
        assert.equal(to_snake_case("This is Human case."), "this_is_human_case");
        assert.equal(to_snake_case("MixedUP CamelCase, with some Spaces"), "mixed_up_camel_case_with_some_spaces");
        assert.equal(to_snake_case("kebab-case"), "kebab_case");
        assert.equal(to_snake_case("SHOUTY_SNAKE_CASE"), "shouty_snake_case");
        assert.equal(to_snake_case("snake_case"), "snake_case");
        assert.equal(to_snake_case("XMLHttpRequest"), "xml_http_request");
        assert.equal(to_snake_case("FIELD_NAME11"), "field_name11");
        assert.equal(to_snake_case("99BOTTLES"), "99bottles");
        assert.equal(to_snake_case("FieldNamE11"), "field_nam_e11");
        assert.equal(to_snake_case("abc123def456"), "abc123def456");
        assert.equal(to_snake_case("abc123DEF456"), "abc123_def456");
        assert.equal(to_snake_case("abc123Def456"), "abc123_def456");
        assert.equal(to_snake_case("abc123DEf456"), "abc123_d_ef456");
        assert.equal(to_snake_case("ABC123def456"), "abc123def456");
        assert.equal(to_snake_case("ABC123DEF456"), "abc123def456");
        assert.equal(to_snake_case("ABC123Def456"), "abc123_def456");
        assert.equal(to_snake_case("ABC123DEf456"), "abc123d_ef456");
        assert.equal(to_snake_case("ABC123dEEf456FOO"), "abc123d_e_ef456_foo");
        assert.equal(to_snake_case("abcDEF"), "abc_def");
        assert.equal(to_snake_case("ABcDE"), "a_bc_de")
    }
    test "shouty_snake" {
        assert.equal(to_shouty_snake_case("CamelCase"), "CAMEL_CASE");
        assert.equal(to_shouty_snake_case("This is Human case."), "THIS_IS_HUMAN_CASE");
        assert.equal(to_shouty_snake_case("kebab-case"), "KEBAB_CASE");
        assert.equal(to_shouty_snake_case("snake_case"), "SNAKE_CASE");
        assert.equal(to_shouty_snake_case("XMLHttpRequest"), "XML_HTTP_REQUEST")
    }
    test "upper_camel" {
        assert.equal(to_upper_camel_case("CamelCase"), "CamelCase");
        assert.equal(to_upper_camel_case("This is Human case."), "ThisIsHumanCase");
        assert.equal(to_upper_camel_case("kebab-case"), "KebabCase");
        assert.equal(to_upper_camel_case("SHOUTY_SNAKE_CASE"), "ShoutySnakeCase");
        assert.equal(to_upper_camel_case("XMLHttpRequest"), "XmlHttpRequest")
    }
    test "lower_camel" {
        assert.equal(to_lower_camel_case("CamelCase"), "camelCase");
        assert.equal(to_lower_camel_case("This is Human case."), "thisIsHumanCase");
        assert.equal(to_lower_camel_case("snake_case"), "snakeCase");
        assert.equal(to_lower_camel_case("XMLHttpRequest"), "xmlHttpRequest")
    }
    test "title_train_shouty_kebab" {
        assert.equal(to_title_case("CamelCase"), "Camel Case");
        assert.equal(to_train_case("snake_case"), "Snake-Case");
        assert.equal(to_shouty_kebab_case("snake_case"), "SNAKE-CASE")
    }
}
