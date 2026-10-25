require "../heap_census"

class Iyi::Command
  private def heap
    if options.any? { |arg| arg.in?("--help", "-h") }
      puts <<-HELP
        Usage: ris heap [--user] FILE.ri

        Compile without codegen; list reachable typed heap sites, sorted.
        Format: path:line:col  kind  detail; then counts per kind.
        --user lists only .ri sites outside std. Libraries group by file.
        Scheduler queues, fiber stacks, tape mappings and runtime metadata
        are excluded: they are not program values. Foreign allocations
        and opaque artifact bodies cannot be inspected. Standard stream
        objects/buffers and stack-guard metadata are runtime support.
        migration/opaque/exemption are overlapping audit categories;
        total counts allocation kinds only, not audit categories.
        RIS_HEAP_STATS=1 prints program allocations and bytes at exit.
        build/run --no-gc links gc_none on Linux and traps heap allocation.
        HELP
      return
    end
    user = options.delete("--user")
    _, result = compile_no_codegen "heap"
    census = HeapCensus.new(result.program)
    census.run(result.node)
    counts = Hash(String, Int32).new(0)
    groups = Hash(String, Int32).new(0)
    census.sites.to_a.sort_by { |key, _| key }.each do |key, detail|
      file, line, col, kind = key
      is_user = file.ends_with?(".ri") && !file.includes?("/std/")
      next if user && !is_user
      counts[kind] += 1
      if is_user
        puts "#{file}:#{line}:#{col}  #{kind}  #{detail}"
      else
        groups[file] += 1
      end
    end
    groups.keys.sort.each { |file| puts "#{file}: #{groups[file]} sites" }
    %w(class string array hash closure other).each do |kind|
      puts "#{kind}: #{counts[kind]}"
    end
    allocation_total = counts.values.sum
    %w(migration opaque exemption).each do |kind|
      allocation_total -= counts[kind]
      puts "#{kind}: #{counts[kind]}"
    end
    puts "total: #{allocation_total}"
  end
end
