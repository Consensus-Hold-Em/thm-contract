/// Module: consensus_holdem
module consensus_holdem::consensus_holdem {

    // use sui::table::{Table};
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
        players: vector<address>,
        player_limit: u8,
        pot_size: Balance<SUI>, // ? maybe this is Coin since this would be actual sui tokens being sent
        round: u8, // tracks the betting round
        turn: u8 // tracks the player index who's turn it is
    }

    fun init(ctx: &mut TxContext) {

    }

    // someone creates the table
    public entry fun create_table(coin: Coin<SUI>, ctx: &mut TxContext) {
        let mut v = vector::empty<address>();
        v.push_back(ctx.sender());

        let card_table = CardTable {
            id: object::new(ctx),
            players: v,
            player_limit: 6,
            pot_size: coin.into_balance(),
            round: GAME_NOT_STARTED,
            turn: 0,
        };

        transfer::share_object(card_table)
    }

    // someone can join an existing table
    public entry fun join_table(card_table: &mut CardTable, ctx: &mut TxContext) {
        card_table.players.push_back(ctx.sender());
    }

    public entry fun small_blind(card_table: &mut CardTable) {
        card_table.players.borrow(0);
    }

    // set the new small blind
    public entry fun start_game(card_table: &mut CardTable, ctx: &mut TxContext) {
        assert!(card_table.round >= GAME_FINISHED, 1);
        let length = card_table.players.length();
        
        // set small blind which is just the first player in the array
        let p = card_table.players.pop_back();
        card_table.players.insert(p, 0);
        card_table.turn = 0;
    }

    // 1) get table, 2) check valid player address, 3) add their bet to the pot size
    public entry fun bet(table_id: UID, ctx: &mut TxContext) {}



}

