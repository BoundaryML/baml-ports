// Port of goldmark util/html5entities.go.
//
// Go builds a `map[string]*HTML5Entity` lazily (sync.Once) from packed
// generated tables. BAML has no package-level state, so lookup dispatches
// straight into the generated decision tree (html5entities.gen.baml).

/// HTML5Entity struct represents HTML5 entitites.
class HTML5Entity {
    name: string,
    characters: uint8array,
}

/// LookUpHTML5EntityByName returns an HTML5Entity if an entity named
/// given name is found, otherwise null (Go returns `(nil, false)`).
function lookup_html5_entity_by_name(name: string) -> HTML5Entity? {
    let chars = html5_entity_characters(name);
    if (chars == null) {
        return null;
    }
    HTML5Entity { name: name, characters: chars.to_utf8() }
}
