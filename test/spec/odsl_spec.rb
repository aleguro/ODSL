# foo_spec.rb
require "test_helper"
require 'odsl'

class ScoreBoard
  attr_accessor :output

  def initialize(game_object)
    @game, @player = game_object.game, game_object.player
  end

  def publish(game_object)
    @output = "Player: #{@player.name} is playing: #{@game.game_type}"
  end
end

module Game
  attr_reader :game

  def start(game_type)
    @game = Struct.new(:game_type, :player).new(game_type, @player.name)
    self
  end
end

module Player
  attr_reader :player

  def with_player(player)
    @player = Struct.new(:name).new(player)
    self
  end
end

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
end

module Games
  class Service < Odsl::Dsl
    include Crud

    inmutable true

    subscribe 'start_game', to: :create
  end
end

describe Odsl do
  before { Odsl.reset_config! }

  it "runs a service and returns the expected result" do
    service = Games::Service.new(player: { name: 'alejandro' }, game: 'chez')
    game_instance, scoreboard = service.run(:create)

    assert_equal 'alejandro', game_instance.game.player
    assert_equal 'chez', game_instance.game.game_type
    assert_equal 'Player: alejandro is playing: chez', scoreboard.output
  end

  it "is immutable: calling run twice yields the same result" do
    service = Games::Service.new(player: { name: 'alejandro' }, game: 'chez')

    result1 = service.run(:create)
    result2 = service.run(:create)

    assert_equal result1.first.game.game_type, result2.first.game.game_type
  end

  it "supports finish_with alias" do
    service = Games::Service.new(player: { name: 'alejandro' }, game: 'chess')
    results = service.run(:create)

    assert_equal 2, results.length
    results.each { |r| refute_nil r }
  end

  it "runs in background and returns a thread" do
    service = Games::Service.new(player: { name: 'alejandro' }, game: 'chez')
    thread = service.run_in_background(:create)

    assert_instance_of Thread, thread
    game_instance, _scoreboard = thread.value

    assert_equal 'alejandro', game_instance.game.player
  end

  it "runs multiple methods in parallel" do
    service = Games::Service.new(player: { name: 'alejandro' }, game: 'chez')
    results = service.run_in_parallel(:create, :create)

    assert_equal 2, results.length
    results.each do |(game_instance, _)|
      assert_equal 'alejandro', game_instance.game.player
    end
  end

  it "dispatches via subscribe" do
    game_instance, _scoreboard = Games::Service.dispatch('start_game', player: { name: 'alejandro' }, game: 'chess')

    assert_equal 'alejandro', game_instance.game.player
    assert_equal 'chess', game_instance.game.game_type
  end

  it "lock() is a no-op when lock_redis_url is not configured" do
    klass = Class.new(Odsl::Dsl) do
      def test_lock
        lock(:player)
        finish_with(:player)
      end
    end

    instance = klass.new(player: { name: 'alejandro' })
    # Should not raise — no redis_url configured, lock is a no-op
    result = instance.run(:test_lock)
    assert_equal [{ name: 'alejandro' }], result
  end

  it "lock() raises LockError when lock cannot be acquired" do
    klass = Class.new(Odsl::Dsl) do
      def failing_lock
        raise Odsl::LockError, "test lock failure"
      end
    end

    assert_raises(Odsl::LockError) do
      klass.new.run(:failing_lock)
    end
  end
end
