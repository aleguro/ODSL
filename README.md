# Object DSL

This is a prototype oriented to use OOP and a functional programming approach by providing a DSL to decouple code logic from coding itself while enforcing good practices and providing:

    - Design patterns
    - Inmutability
    - Dry off
    - Decouple aspects from code ( background, paralelization )

# Your code

```
class ScoreBoard

  def initialize(game_object)
    @game, @player = game_object.game, game_object.player
  end

  def publish
    STDOUT.puts "Player: @player.name is playing: #{@game.game_type}"
  end
end

module Game
  def start(game_type)
    @game = Struct.new(game_type: game_type, player: @player.name)
    self
  end
end

module Player
  def with_player(player)
    @player = Struct.new(name: player)
    self
  end
end

module Game
  module Crud     
    def create    
      build(Game, Players)
        .get(:game_object)

      with(:args, :game_object)
        .set(:new_game)
        .get(:game_instance)

      with(:game_object)
        .instanciate(ScoreBoard)
        .get(:score_board_object)

      with(:score_board_object)
        .call(:publish)

      finish_with(:game_instance) 
    end

    def delete(id)
    end

    private

    def new_game(args, game_object)

      game_object
        .with_player(args[:player])
        .start(args[:game_name])  
    end    
  end
end
  
module Game
  class Service < Odsl:Dsl
    include Crud

    inmutable true 
  end
end
```

# How to use call it.

```
Games::Service
  .new(player: { name: 'alejandro' } , game: 'chez')
  .run(:create)
```

# Future development

 - Run in background mode

 ```.run_in_background(:method)``` 
 
 - Run sevreral methods in paralell 

 ```.run_in_parallel(:method_a, :method_b)```

 - Make service objects subscribe to messaages

 module Game
  class Service < Odsl:Dsl
    include Crud

    subscribe 'start_game', to: :create
    subscribe 'end_game', to: end_game
  end
end
```