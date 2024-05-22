# Object DSL

This is a prototype oriented to use OOP and a functional programming approach by providing a DSL to decouple coding logic from coding while enforcing inmutability.

  - It also provides ways to create complex objects using factory patterns.
  - Aim to improve coding by running any code as an aspect.

# Sample code

```
class CreateGameBoard < Rdsl:Dsl
  include Game
  include Players

  inmutable: true
  background: true

  main do

    with(:args)
      .set(:actors)
      .get(:player, :game)

    with(:player, :game, :args)
      .create(:board)
      .get(:id)

    finish_with(:id)
  end

  private

  def actors(args)
    
    # TODO: Add your business code to get a player and a game instances
   
    [ player, 
      game ]
  end

  def board(player, game, args)

    id = create_new_game_board 

    [ id ]
  end
end
```
  
## Future implementations

# Generic background processing

```
background do

  # Your code

end
```

# Parallel execution

```
parallelize do

  # block A
  run do
  end

  # block B
  run do
  end

end
```
