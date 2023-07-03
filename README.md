# Ruby DSL

This is just a proto type to write code in a DSL declarative syntax stlye, for the time being is only meant to be for educational purpose and is not meant to be use professionally.

# How It would look like

```
class CreateGameBoard < Rdsl:Dsl
  include Game
  include Players

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