// Port of clap_builder/src/util/graph.rs

class Child<T> {
    id: T,
    children: int[],
}

class ChildGraph<T> {
    _0: Child<T>[],

    function with_capacity(s: int) -> ChildGraph<T> { ChildGraph { _0: [] } }

    function insert(self, req: T) -> int {
        let pos = self._0.find_index((e) -> { e.id == req });
        if let p: int = pos {
            p
        } else {
            let idx = self._0.length();
            self._0.push(Child { id: req, children: [] });
            idx
        }
    }

    function insert_child(self, parent: int, child: T) -> int {
        let c_idx = self._0.length();
        self._0.push(Child { id: child, children: [] });
        self._0[parent].children.push(c_idx);
        c_idx
    }

    function iter(self) -> T[] {
        self._0.map((r) -> { r.id })
    }

    function contains(self, req: T) -> bool {
        self._0.some((r) -> { r.id == req })
    }
}
