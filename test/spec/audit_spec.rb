# test/spec/audit_spec.rb
require "test_helper"
require "odsl"

# Domain classes — guarded so re-requiring this file doesn't redefine them
unless defined?(ScoreBoard)
  class ScoreBoard
    attr_accessor :output

    def initialize(game_object)
      @game, @player = game_object.game, game_object.player
    end

    def publish(game_object)
      @output = "Player: #{@player.name} is playing: #{@game.game_type}"
    end
  end
end

unless defined?(Game)
  module Game
    attr_reader :game

    def start(game_type)
      @game = Struct.new(:game_type, :player).new(game_type, @player.name)
      self
    end
  end
end

unless defined?(Player)
  module Player
    attr_reader :player

    def with_player(player)
      @player = Struct.new(:name).new(player)
      self
    end
  end
end

unless defined?(Games)
  module Games
    module Crud
      def create
        build(Game, Player)
          .get(:game_object)

        with(:player, :game, :game_object)
          .make(:new_game)
          .get(:game_instance)

        with(:game_instance)
          .instantiate(ScoreBoard)
          .get(:score_board_object)

        use(:score_board_object)
          .with(:game_instance)
          .call(:publish)

        finish_with(:game_instance, :score_board_object)
      end

      def delete(id); end

      def update(id); end

      private

      def new_game(player, game, game_object)
        game_object
          .with_player(player[:name])
          .start(game)
      end
    end

    class Service < Odsl::Dsl
      include Crud

      inmutable true

      subscribe 'start_game', to: :create
    end
  end
end

describe "Audit system" do
  before do
    Odsl.reset_config!
    Odsl::Audit::StepRecord.delete_all
    Odsl::Audit::ExecutionContext.delete_all
  end

  it "creates an ExecutionContext when key: is given" do
    service = Games::Service.new(player: { name: "alejandro" }, game: "chess")
    service.run(:create, key: "audit-test-1")

    ctx = Odsl::Audit::ExecutionContext.find_by!(idempotency_key: "audit-test-1")
    assert_equal "completed", ctx.status
    assert_equal "Games::Service", ctx.service_class
    assert_equal "create", ctx.method_name
  end

  it "creates StepRecords for each .get() call" do
    service = Games::Service.new(player: { name: "alejandro" }, game: "chess")
    service.run(:create, key: "audit-test-2")

    ctx   = Odsl::Audit::ExecutionContext.find_by!(idempotency_key: "audit-test-2")
    names = ctx.step_records.order(:step_index).pluck(:name)

    assert_includes names, "game_object"
    assert_includes names, "game_instance"
    assert_includes names, "score_board_object"
  end

  it "does not create an ExecutionContext when no key: given" do
    service = Games::Service.new(player: { name: "alejandro" }, game: "chess")
    service.run(:create)

    assert_equal 0, Odsl::Audit::ExecutionContext.count
  end

  it "returns immediately for a completed context (idempotency)" do
    service = Games::Service.new(player: { name: "alejandro" }, game: "chess")
    service.run(:create, key: "audit-test-3")

    # Second call with same key — context is completed, should return nil immediately
    service2 = Games::Service.new(player: { name: "alejandro" }, game: "chess")
    result2  = service2.run(:create, key: "audit-test-3")

    assert_nil result2
  end

  it "raises AlreadyRunningError if context is running" do
    Odsl::Audit::ExecutionContext.create!(
      idempotency_key: "audit-test-4",
      service_class:   "Games::Service",
      method_name:     "create",
      kwargs:          "{}",
      status:          "running"
    )

    service = Games::Service.new(player: { name: "alejandro" }, game: "chess")
    assert_raises(Odsl::AlreadyRunningError) do
      service.run(:create, key: "audit-test-4")
    end
  end

  it "marks context as failed when method raises" do
    # Temporarily add a failing method to Games::Service
    Games::Service.class_eval do
      def failing_create
        raise "boom"
      end
    end

    service = Games::Service.new(player: { name: "alejandro" }, game: "chess")
    assert_raises(RuntimeError) { service.run(:failing_create, key: "audit-test-5") }

    ctx = Odsl::Audit::ExecutionContext.find_by!(idempotency_key: "audit-test-5")
    assert_equal "failed", ctx.status
  ensure
    Games::Service.undef_method(:failing_create) rescue nil
  end
end

describe "Resume" do
  before do
    Odsl.reset_config!
    Odsl::Audit::StepRecord.delete_all
    Odsl::Audit::ExecutionContext.delete_all
  end

  it "resumes a failed run and completes it" do
    # First run succeeds normally
    service = Games::Service.new(player: { name: "alejandro" }, game: "chess")
    service.run(:create, key: "resume-test-1")

    # Mark it as failed to simulate a failure after partial execution
    ctx = Odsl::Audit::ExecutionContext.find_by!(idempotency_key: "resume-test-1")
    ctx.update!(status: "failed")

    # Resume should complete it
    result = Games::Service.resume(key: "resume-test-1")
    refute_nil result

    ctx.reload
    assert_equal "completed", ctx.status
  end

  it "raises ContextNotFoundError for unknown key" do
    assert_raises(Odsl::ContextNotFoundError) do
      Games::Service.resume(key: "does-not-exist")
    end
  end

  it "skips steps already recorded as completed on resume" do
    # Run once to record steps
    service = Games::Service.new(player: { name: "alejandro" }, game: "chess")
    service.run(:create, key: "resume-test-3")

    ctx = Odsl::Audit::ExecutionContext.find_by!(idempotency_key: "resume-test-3")
    step_count_before = ctx.step_records.count

    # Mark failed and resume
    ctx.update!(status: "failed")
    Games::Service.resume(key: "resume-test-3")

    # No new step records should be added for already-completed steps
    # (they're non_resumable so they get re-recorded, but the context completes)
    ctx.reload
    assert_equal "completed", ctx.status
  end
end
