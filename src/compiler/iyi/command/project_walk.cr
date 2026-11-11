# ris: the one walk over a project's files, shared by `ris test` and (from
# step 6 of doc/drafts/spec-blocks/spec-blocks.md, 5.9) `ris spec`.
#
# It skips what is not the project's own code: `lib/` and `mods/` (other
# projects' code, at any depth), every directory whose name starts with a
# dot, fixture trees (a directory holding a `.ris-fixtures` marker) and
# symlinks. `ris test` globbed `**/*_test.ri` and ran the tests under lib/,
# which belong to another project (bug B1).
class Iyi::Command
  private WALK_SKIPPED_DIRS = {"lib", "mods"}

  # Every file under *dir* (itself never skipped) for which *keep* is true,
  # in walk order; the caller sorts.
  private def project_walk(dir : String, found : Array(String), &keep : String -> Bool) : Nil
    return if File.exists?(File.join(dir, ".ris-fixtures"))
    Dir.children(dir).each do |child|
      next if child.starts_with?('.')
      path = File.join(dir, child)
      next if File.symlink?(path)
      if Dir.exists?(path)
        next if WALK_SKIPPED_DIRS.includes?(child)
        project_walk(path, found, &keep)
      elsif keep.call(child)
        found << path
      end
    end
  end

  # A test program's name: `*_test.ri` or `*_test.iyi`, the suffix in any
  # case so a miscased name is refused later rather than walked past.
  private def test_program_name?(name : String) : Bool
    lower = name.downcase
    lower.ends_with?("_test.ri") || lower.ends_with?("_test.iyi")
  end
end
