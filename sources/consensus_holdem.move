/// Module: consensus_holdem
module consensus_holdem::consensus_holdem {

    use sui::table::{Table};
    use sui::balance::{Balance};
    use sui::coin::{Coin};
    use sui::sui::SUI;

    // rounds
    const PREFLOP_ROUND: u8 = 0;
    const FLOP_ROUND: u8 = 1;
    const TURN_ROUND: u8 = 2;
    const RIVER_ROUND: u8 = 3;
    const GAME_FINISHED: u8 = 4;
    const GAME_NOT_STARTED: u8 = 5;

    public struct CardTable has key, store {
        id: UID,
        players: Table<u8, address>,
        player_limit: u8,
        small_blind: u8,
        pot_size: Balance<SUI>, // ? maybe this is Coin since this would be actual sui tokens being sent
        round: u8, // tracks the betting round
        turn: u8 // tracks the player who's turn it is
    }

    fun init(ctx: &mut TxContext) {

    }

    // someone creates the table
    public entry fun create_table(coin: Coin<SUI>, ctx: &mut TxContext) {

        let mut players = sui::table::new<u8,address>(ctx);
        let length = sui::table::length<u8, address>(&players);
        players.add((length as u8), ctx.sender());

        let card_table = CardTable {
            id: object::new(ctx),
            players: players,
            player_limit: 6,
            small_blind: 0,
            pot_size: coin.into_balance(),
            round: GAME_NOT_STARTED,
            turn: 0,
        };

        transfer::share_object(card_table)
    }

    // someone can join an existing table
    public entry fun join_table(card_table: &mut CardTable, ctx: &mut TxContext) {
        let length = sui::table::length<u8, address>(&card_table.players);
        card_table.players.add((length as u8), ctx.sender());
    }

    // set the new small blind
    public entry fun start_game(card_table: &mut CardTable, ctx: &mut TxContext) {

    }

    // 1) get table, 2) check valid player address, 3) add their bet to the pot size
    public entry fun bet(table_id: UID, ctx: &mut TxContext) {}



}

