# foo_spec.rb
require "test_helper"
require 'odsl'

describe Odsl do
  
  it "does something" do
    
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
    
          value_return(:game_instance) 
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

    game_instance = Games::Service
                      .new(player: { name: 'alejandro' } , game: 'chez')
                      .run(:create)

    assert_equal 'alejandro', game_instance.game.player
    assert_equal 'chez', game_instance.game.game_type
  end
end