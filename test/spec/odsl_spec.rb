# foo_spec.rb
require "test_helper"
require 'odsl'

describe Odsl do
  
  it "does something" do
    
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

          value_return(:game_instance, :score_board_object) 
        end
    
        def delete(id) ; end

        def update(id) ; end
    
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
      end
    end
  
    service = Games::Service.new(player: { name: 'alejandro' } , game: 'chez')

    game_instance, scoreboard = service.run(:create)

    assert_equal 'alejandro', game_instance.game.player
    assert_equal 'chez', game_instance.game.game_type
    assert_equal 'Player: alejandro is playing: chez', scoreboard.output
  end
end