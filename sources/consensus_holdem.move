/// Module: consensus_holdem
module consensus_holdem::consensus_holdem {

    use sui::table::{Table};

    public struct CardTable has key, store {
        id: UID,
        players: Table<u8, address>,
        player_limit: u8,
        small_blind: u8,
        pot_size: u256, // ? maybe this is Coin since this would be actual sui tokens being sent
        round: u8, // tracks the betting round
        turn: u8 // tracks whose turn it is
    }

    fun init(ctx: &mut TxContext) {

    }

    // someone creates the table
    fun create_table(ctx: &mut TxContext) {

        let mut players = sui::table::new<u8,address>(ctx);
        let length = sui::table::length<u8, address>(&players);
        players.add((length as u8), ctx.sender());

        let card_table = CardTable {
            id: object::new(ctx),
            players: players,
            player_limit: 6,
            small_blind: 0,
            pot_size: 0,
            round: 0,
            turn: 0,
        };

        transfer::share_object(card_table)
    }

    // someone can join an existing table
    fun join_table(table_id: UID) {}

    // set the new small blind
    fun start_game(table_id: UID) {

    }

    // 1) get table, 2) check valid player address, 3) add their bet to the pot size
    fun bet(table_id: UID) {}

}

