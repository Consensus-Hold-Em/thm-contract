module consensus_holdem::events {
    use sui::event::{Self};

    public struct CreateTableEvent has copy, drop {
        table_id: ID,
        player: address,
    }

    public fun emit_create_table(table_id: ID, player: address) {
        event::emit(CreateTableEvent {
            table_id,
            player,
        });
    }

    public struct JoinTableEvent has copy, drop {
        table_id: ID,
        player: address,
    }

    public fun emit_join_table(table_id: ID, player: address) {
        event::emit(JoinTableEvent {
            table_id,
            player,
        });
    }

    public struct NewHandEvent has copy, drop {
        table_id: ID,
        player_id: u64,
        public_key: vector<u8>,
    }

    public fun emit_new_hand(table_id: ID, player_id: u64, public_key: vector<u8>) {
        event::emit(NewHandEvent {
            table_id,
            player_id,
            public_key
        });
    }

    public struct StartHandEvent has copy, drop {
        table_id: ID,
        player_id: u64,
        hand_state: vector<u8>,
        commitment: vector<u8>
    }

    public fun emit_start_hand(table_id: ID, 
        player_id: u64,         
        hand_state: vector<u8>,
        commitment: vector<u8>) {
            
            event::emit(StartHandEvent {
                table_id,
                player_id,
                hand_state,
                commitment
            }); 

        }

    public struct StartGameEvent has copy, drop {
        table_id: ID,
        players: vector<address>,
    }

    public fun emit_start_game(table_id: ID, players: vector<address>) {
        event::emit(StartGameEvent {
            table_id,
            players
        })
    }

    public struct ShuffleAndDecryptEvent has copy, drop {
        table_id: ID,
        player_id: u64,
        deck: vector<u8>
    }

    public fun emit_shuffle_decrypt(
        table_id: ID, 
        player_id: u64,
        deck: vector<u8>
        ) {
            event::emit(ShuffleAndDecryptEvent {
                table_id,
                player_id,
                deck
            });
        }
    
    public struct StartBettingEvent has copy, drop {
        table_id: ID,
    }

    public fun emit_start_betting(table_id: ID) {
        event::emit(StartBettingEvent {
            table_id
        });
    }
}