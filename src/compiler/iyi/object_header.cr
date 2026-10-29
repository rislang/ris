module Iyi::Collector
  # The marking colours, valued so a fresh all-zero word reads as white: an
  # allocator stores nothing but the type id to make a new object white.
  enum Color : UInt8
    White = 0
    Gray  = 1
    Black = 2
  end

  struct ObjectHeader
    # The bit layout of the mark word, named exactly once. A shift or mask
    # written a second time anywhere else is how a collector acquires a bug
    # that only appears under load.
    COLOR_MASK    = 0b11_u64
    HAS_FINALIZER = 1_u64 << 2
    IS_PINNED     = 1_u64 << 3

    # The type id's home: the high half of the word.
    TYPE_SHIFT = 32
    TYPE_MASK  = UInt64::MAX << TYPE_SHIFT

    # Between the flags and the type id is the reserved payload: 27 bits.
    PAYLOAD_SHIFT = 5
    PAYLOAD_MAX   = (1_u64 << (TYPE_SHIFT - PAYLOAD_SHIFT)) - 1

    # The bits a payload write must not touch: colour, flags and type.
    NON_PAYLOAD_MASK = ((1_u64 << PAYLOAD_SHIFT) - 1) | TYPE_MASK

    @mark_word : Atomic(UInt64)

    def initialize(type_id : UInt32)
      # White, no flags, no payload: the type id alone.
      @mark_word = Atomic(UInt64).new(type_id.to_u64 << TYPE_SHIFT)
    end

    def type_id : UInt32
      (@mark_word.get >> TYPE_SHIFT).to_u32
    end

    # The colour, read out of the word without disturbing flags or payload.
    def color : Color
      Color.from_value((@mark_word.get & COLOR_MASK).to_u8)
    end

    # CAS white to gray. True when this call did the shading; false when the
    # object was already gray or black, in which case the caller must not
    # scan it: the worker that won the race owns the scan, and scanning the
    # object twice is the bug the race answer exists to prevent.
    def shade_gray : Bool
      transition(Color::White, Color::Gray)
    end

    # CAS gray to black, once every pointer field has been scanned. True when
    # this call blackened the object.
    def shade_black : Bool
      transition(Color::Gray, Color::Black)
    end

    def has_finalizer? : Bool
      flag?(HAS_FINALIZER)
    end

    def pinned? : Bool
      flag?(IS_PINNED)
    end

    def mark_has_finalizer : Nil
      set_flag(HAS_FINALIZER)
    end

    def pin : Nil
      set_flag(IS_PINNED)
    end

    # The reserved middle bits, with colour and flags shifted away and the
    # type id masked off.
    def payload : UInt64
      (@mark_word.get & ~TYPE_MASK) >> PAYLOAD_SHIFT
    end

    # Replaces the reserved payload, leaving colour and flags untouched.
    # Nothing writes a payload yet; the round trip is a tested property
    # rather than an assumption, which is what keeps the forwarding pointer
    # possible. Overflow is refused rather than truncated, because a
    # truncated forwarding pointer is a corrupted heap.
    def payload=(value : UInt64) : Nil
      if value > PAYLOAD_MAX
        raise ArgumentError.new("payload #{value} does not fit in #{TYPE_SHIFT - PAYLOAD_SHIFT} bits")
      end
      word = @mark_word.get
      loop do
        desired = (word & NON_PAYLOAD_MASK) | (value << PAYLOAD_SHIFT)
        word, won = @mark_word.compare_and_set(word, desired)
        return if won
      end
    end

    # The colour check is inside the loop and the expected word is refreshed
    # by every lost CAS, so a flag or payload set concurrently with the
    # transition is carried into the next attempt instead of being written
    # over. Sequentially consistent, like every `Atomic` default; weaker
    # orderings are a Stage 7 measurement, not a Stage 1 decision.
    private def transition(from : Color, to : Color) : Bool
      word = @mark_word.get
      loop do
        return false unless (word & COLOR_MASK) == from.value.to_u64
        desired = (word & ~COLOR_MASK) | to.value.to_u64
        word, won = @mark_word.compare_and_set(word, desired)
        return true if won
      end
    end

    private def flag?(bit : UInt64) : Bool
      (@mark_word.get & bit) != 0
    end

    private def set_flag(bit : UInt64) : Nil
      word = @mark_word.get
      loop do
        return if (word & bit) == bit
        word, won = @mark_word.compare_and_set(word, word | bit)
        return if won
      end
    end
  end
end
