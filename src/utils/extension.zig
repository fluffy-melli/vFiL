pub fn is_dot(name: []const u16) bool {
    if (name.len == 0 or name.len > 3) {
        return false;
    }

    if (name.len == 1 and name[0] == '.') {
        return true;
    }

    if (name.len == 2 and name[0] == '.' and name[1] == '.') {
        return true;
    }

    return false;
}
