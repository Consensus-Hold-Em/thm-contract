module consensus_holdem::war {
    use consensus_holdem::crypto::{Self};
    use consensus_holdem::events::{Self};
    use sui::table::{Self,Table};
    use sui::balance::{Balance};
    use sui::coin::{Coin};
    use sui::sui::SUI;

    // rounds
    const GAME_NOT_STARTED: u8 = 0;
    const GAME_STARTED: u8 = 1;
    const DECK_SETUP: u8 = 2;
    const BETTING_PHASE: u8 = 3;
    const REVEAL_CARDS: u8 = 4;
    const DECLARE_WINNER: u8 = 5;

    public struct CardTable has key,store {
        id: UID,
        players: vector<address>,
        current_keys: vector<vector<u8>>,
        chips: Table<address, Balance<SUI>>,
        buy_in: u64,
        player_limit: u64,
        round_state: RoundState,
        hand_state: HandState,
        // table_owner: address, // is this needed? permission related functionality
    }

    public struct EncryptedCard has copy, drop, store {
        in: vector<u8>,
        c1: vector<u8>,
    }

    public struct HandState has key,store {
        id: UID,
        player_cards: vector<EncryptedCard>,
        revealed_cards: vector<u64>,
        deck: vector<u8>,
        hand_state: vector<u8>,
    }

    public struct BettingState has key,store {
        id: UID,
        // total_pot: u64, // ? not worth maintaining
        current_bet: u64,
        player_bets: Table<address, u64>,
        player_calls: Table<address, bool>
    }

    public struct RoundState has key,store {
        id: UID,
        current_round: u8,
        player_init: Table<address, bool>,
        init_confirmed: u8,
        current_turn: u64,
        betting_state: BettingState,
        player_folds: Table<address, bool>,
    }

    public entry fun create_table(coin: Coin<SUI>, buy_in: u64, player_limit: u64, ctx: &mut TxContext) {
        let mut players = vector::empty<address>();
        players.push_back(ctx.sender());
        let chips = sui::table::new<address, Balance<SUI>>(ctx);

        let mut card_table = CardTable {
            id: object::new(ctx),
            players: players,
            current_keys: vector::empty<vector<u8>>(),
            chips: chips,
            buy_in: buy_in,
            player_limit: player_limit,
            round_state: RoundState {
                id: object::new(ctx),
                current_round: GAME_NOT_STARTED,
                player_init: table::new(ctx),
                init_confirmed: 0,
                current_turn: 0,
                player_folds: table::new(ctx),
                betting_state: BettingState {
                    id: object::new(ctx),
                    // total_pot: 0,
                    current_bet: 0,
                    player_bets: table::new(ctx),
                    player_calls: table::new(ctx),
            }
            },
            hand_state: HandState {
                id: object::new(ctx),
                player_cards: vector::empty<EncryptedCard>(),
                revealed_cards: vector::empty<u64>(),
                deck: vector::empty<u8>(),
                hand_state: vector::empty<u8>(),
            },
        };

        card_table.current_keys.push_back(vector::empty<u8>());

        buy_in(&mut card_table, coin, ctx);

        events::emit_create_table(object::id(&card_table), ctx.sender());

        transfer::share_object(card_table);
    }

    // handles adding a balance to a new or existing stack
    public fun buy_in(card_table: &mut CardTable, coin: Coin<SUI>, ctx: &mut TxContext) {
        let coin_amount = coin.value();
        assert!(coin_amount >= card_table.buy_in, 0);
        if (card_table.chips.contains(ctx.sender()) == true) {
            let current_amount = card_table.chips.borrow_mut(ctx.sender());
            current_amount.join(coin.into_balance());
        } else {
            card_table.chips.add(ctx.sender(), coin.into_balance());
        }
    }

    public entry fun join_table(card_table: &mut CardTable, coin: Coin<SUI>, ctx: &mut TxContext) {
        assert!(card_table.players.length() <= card_table.player_limit, 0);
        assert!(card_table.round_state.current_round == GAME_NOT_STARTED, 0);
        card_table.buy_in(coin, ctx);
        card_table.players.push_back(ctx.sender());
        card_table.current_keys.push_back(vector::empty<u8>());

        events::emit_join_table(object::id(card_table), ctx.sender());
    }

    // ? possible consider changing the player_id index to use ctx.sender() 
    // and then use a Table for the players keys
    public fun new_hand(card_table: &mut CardTable, public_key: vector<u8>, ctx: &mut TxContext) {
        add_public_key(card_table, public_key, ctx);
        handle_init_state(card_table, ctx);
    }

    fun add_public_key(card_table: &mut CardTable, public_key: vector<u8>, ctx: &TxContext) {
        let mut i = 0;
        let mut new_keys = vector::empty<vector<u8>>();
        while (i < card_table.current_keys.length()) {
            let player = card_table.players[i];
            if (ctx.sender() == player) {
                new_keys.push_back(public_key);
            } else {
                let item = card_table.current_keys[i];
                new_keys.push_back(item);      
            };
            i = i + 1;
        };

        card_table.current_keys = new_keys;

        events::emit_new_hand(object::id(card_table),
            ctx.sender(),
            public_key
        );

    }

    // This essentially handles the game state transition from not start to started
    // all players must confirm
    fun handle_init_state(card_table: &mut CardTable, ctx: &TxContext) {
        assert!(card_table.round_state.current_round == GAME_NOT_STARTED, 0);

        let player = ctx.sender();
        let init_map = &mut card_table.round_state.player_init;
        if (init_map.contains(player)) {
            let val = init_map.borrow_mut(player);
            assert!(*val == false, 1);
            *val = true;
        } else {
            init_map.add(player, true);
        };
        card_table.round_state.init_confirmed = card_table.round_state.init_confirmed + 1;

        let all_players_init = card_table.players.length() as u8 == card_table.round_state.init_confirmed;
        if (all_players_init) {
            card_table.round_state.current_round = GAME_STARTED;
            events::emit_round_transition(object::id(card_table), GAME_STARTED);
        }
    }

    // start_hand sets up the initial values for the hand for each players encrypted
    // card locations. This is called by every player in order 
    public fun start_hand(card_table: &mut CardTable, 
        commitment: vector<u8>, 
        hand_state: vector<u8>, 
        ctx: &mut TxContext
        ) {
        
        assert!(card_table.round_state.current_round == GAME_STARTED, 0);
        assert!(card_table.players[card_table.round_state.current_turn] == ctx.sender(), 1);

        events::emit_start_hand(
            object::id(card_table),
            hand_state,
            commitment
        );

        card_table.current_hand_state.hand_state = hand_state;

        if (card_table.round_state.current_turn == card_table.players.length()-1) {
            card_table.round_state.current_round = DECK_SETUP;
            card_table.round_state.current_turn = 0;
            
            events::emit_start_game(
                object::id(card_table),
                card_table.players
            );
            events::emit_round_transition(object::id(card_table), DECK_SETUP);
        } else {
            card_table.round_state.current_turn = card_table.round_state.current_turn + 1;
        }
    }

    public fun ShuffleAndDecrypt(card_table: &mut CardTable, shuffled: vector<u8>, ctx: &mut TxContext) {
        assert!(card_table.round_state.current_round == DECK_SETUP, 0);
        assert!(card_table.players[card_table.round_state.current_turn] == ctx.sender(), 1);
        
        card_table.hand_state.deck = shuffled;
        
        events::emit_shuffle_decrypt(
            object::id(card_table),
            ctx.sender(),
            shuffled
        );

        if (card_table.round_state.current_turn == card_table.players.length()-1) {
            card_table.round_state.current_round = BETTING_PHASE;
            card_table.round_state.current_turn = 0;

            events::emit_start_betting(object::id(card_table));
        } else {
            card_table.round_state.current_turn = card_table.round_state.current_turn + 1;
        }
    }

    fun handle_turn(card_table: &mut CardTable, ctx: &mut TxContext) {
        let turn = card_table.round_state.current_turn;

        // handle the next player turn skip over folds
        loop {
            turn = turn + 1;
            let player = card_table.players[turn];
            let folded = card_table.round_state.player_folds.borrow(player);
            if (*folded == false) {
                card_table.round_state.current_turn = turn;
                break
            };
            // check if it rotated thru everyone and there is only one player standing
            if (turn == card_table.round_state.current_turn) {
                payout(card_table, ctx);
                break;
            }
        };

        check_calls(card_table, ctx);
    }

    // checks the status of player calls, if everyone has called then move to reveal hand
    fun check_calls(card_table: &mut CardTable, ctx: &mut TxContext) {

    }

    public entry fun fold(card_table: &mut CardTable, ctx: &mut TxContext) {
        assert!(card_table.round_state.current_round == BETTING_PHASE, 0);
        assert!(card_table.players[card_table.round_state.current_turn] == ctx.sender(), 1);

        let player = card_table.round_state.player_folds.borrow_mut(ctx.sender());
        assert!(player == false, 2);
        *player = true;
        handle_turn(card_table, ctx);
    }

    public entry fun call(card_table: &mut CardTable, ctx: &mut TxContext) {
        assert!(card_table.round_state.current_round == BETTING_PHASE, 0);
        assert!(card_table.players[card_table.round_state.current_turn] == ctx.sender(), 1);

        let player_current_bet = card_table.round_state.betting_state.player_bets.borrow_mut(ctx.sender());
        let current_bet_amount = card_table.round_state.betting_state.current_bet;

        let chips_amount = card_table.chips.borrow(ctx.sender());
        if (chips_amount.value() > current_bet_amount) {
            *player_current_bet = current_bet_amount;
        } else if (chips_amount.value() < current_bet_amount) {
            // going all in, whats left
            // TODO someday this needs to be improved to 
            // have side pots
            *player_current_bet = chips_amount.value();
        };
        handle_turn(card_table, ctx);
    }

    public entry fun bet(card_table: &mut CardTable, amount: u64, ctx: &mut TxContext) {
        assert!(card_table.round_state.current_round == BETTING_PHASE, 0);
        assert!(card_table.players[card_table.round_state.current_turn] == ctx.sender(), 1);
        assert!(amount > 0, 2);

        let current_bet = &mut card_table.round_state.betting_state.current_bet;
        *current_bet = amount + *current_bet;

        let player_current_bet = card_table.round_state.betting_state.player_bets.borrow_mut(ctx.sender());
        *player_current_bet = *current_bet;

        handle_turn(card_table, ctx);
    }

    public entry fun payout(card_table: &mut CardTable, ctx: &mut TxContext) {
        events::emit_round_transition(object::id(card_table), DECLARE_WINNER);
    }
}