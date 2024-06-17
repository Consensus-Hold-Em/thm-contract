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
        current_hand_state: CurrentHandState,
        // table_owner: address, // is this needed? permission related functionality
    }

    public struct EncryptedCard has copy, drop, store {
        in: vector<u8>,
        c1: vector<u8>,
    }

    public struct CurrentHandState has key,store {
        id: UID,
        player_cards: vector<EncryptedCard>,
        revealed_cards: vector<u64>,
        deck: vector<u8>,
        hand_state: vector<u8>,
        bettingState: BettingState,
    }

    public struct BettingState has key,store {
        id: UID,
        current_pot: u64,
        turn: Option<address> // whose turn it is
    }

    public struct RoundState has key,store {
        id: UID,
        current_round: u8,
        player_init: Table<address, u8>,
        init_confirmed: u8,
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
                init_confirmed: 0
            },
            current_hand_state: CurrentHandState {
                id: object::new(ctx),
                player_cards: vector::empty<EncryptedCard>(),
                revealed_cards: vector::empty<u64>(),
                deck: vector::empty<u8>(),
                hand_state: vector::empty<u8>(),
                bettingState: BettingState {
                    id: object::new(ctx),
                    current_pot: 0,
                    turn: option::none<address>(),
                }
            }
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
    public fun new_hand(card_table: &mut CardTable, player_id: u64, public_key: vector<u8>, 
        ctx: &mut TxContext) {

        add_public_key(card_table, player_id, public_key);

        handle_init_state(card_table, player_id);
    }

    fun add_public_key(card_table: &mut CardTable, player_id: u64, public_key: vector<u8>) {
        let mut i = 0;
        let mut new_keys = vector::empty<vector<u8>>();
        while (i < card_table.current_keys.length()) { 
            let item = card_table.current_keys[i];    
            if (player_id == i) {
                new_keys.push_back(public_key);
            } else {
                new_keys.push_back(item);      
            };
            i = i + 1;
        };

        card_table.current_keys = new_keys;

        events::emit_new_hand(object::id(card_table),
            player_id,
            public_key
        );

    }

    // This essentially handles the game state transition from not start to started
    // all players must confirm
    fun handle_init_state(card_table: &mut CardTable, player_id: u64) {
        assert!(card_table.round_state.current_round == GAME_NOT_STARTED, 0);

        let player = card_table.players[player_id];
        let init_map = &mut card_table.round_state.player_init;
        if (init_map.contains(player)) {
            let val = init_map.borrow_mut(player);
            if (val == 0) {
                val = &mut 1;
                card_table.round_state.init_confirmed = card_table.round_state.init_confirmed + 1
            }
        } else {
            init_map.add(player, 1);
        };

        let all_players_init = card_table.players.length() as u8 == card_table.round_state.init_confirmed;
        if (all_players_init) {
            card_table.round_state.current_round = GAME_STARTED;
            events::emit_round_transition(object::id(card_table), GAME_STARTED);
        }
    }

    // start_hand sets up the initial values for the hand for each players encrypted
    // card locations. This is called by every player in order 
    public fun start_hand(card_table: &mut CardTable, 
        player_id: u64,
        commitment: vector<u8>, 
        hand_state: vector<u8>, 
        ctx: &mut TxContext
        ) {
        
        assert!(card_table.round_state.current_round == GAME_STARTED, 0);

        // TODO: assert player_id submitted matches current turn order, which we are not tracking now.
        
        let addr = ctx.sender();

        events::emit_start_hand(
            object::id(card_table),
            player_id,
            hand_state,
            commitment
        );

        card_table.current_hand_state.hand_state = hand_state;

        if (player_id == card_table.players.length()-1) {
            // Subtract the balance for the small_blind and big_blind

            card_table.round = DECK_SETUP;
            
            events::emit_start_game(
                object::id(card_table),
                card_table.players
            );
        }
    }

    public fun ShuffleAndDecrypt(card_table: &mut CardTable, player_id: u64, shuffled: vector<u8>, ctx: &mut TxContext) {
        events::emit_shuffle_decrypt(
            object::id(card_table),
            player_id,
            shuffled
        );

        card_table.current_hand_state.deck = shuffled;

        if (player_id == card_table.players.length() - 1) {
            card_table.round_state.current_round = BETTING_PHASE; 

            events::emit_start_betting(object::id(card_table));
        }
    }


    public entry fun bet() {}

    public entry fun reward() {}
}