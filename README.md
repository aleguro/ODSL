# Object DSL

This is a prototype oriented to use OOP and a functional programming approach by providing a DSL to decouple code logic from coding itself while enforcing good practices and providing:

    - Design patterns
    - Inmutability
    - Dry off
    - Decouple aspects from code ( background, paralelization )

# Your code

```
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

 .run_in_background() 
 .run_in_parallel()