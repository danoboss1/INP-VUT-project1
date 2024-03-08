-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2023 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Daniel Sehnoutek <xsehno02 AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic;                      -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'

   -- stavove signaly
   READY    : out std_logic;                      -- hodnota 1 znamena, ze byl procesor inicializovan a zacina vykonavat program
   DONE     : out std_logic                       -- hodnota 1 znamena, ze procesor ukoncil vykonavani programu (narazil na instrukci halt)
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is
    -- TUTO DAJ MOJE SIGNALY  
    signal mx_1_sel  : std_logic;
    signal mx_2_sel  : std_logic_vector(1 downto 0);
    
    signal ptr_inc   : std_logic;
    signal ptr_dec   : std_logic;
    signal ptr_out   : std_logic_vector(12 downto 0);
    
    signal pc_inc    : std_logic;
    signal pc_dec    : std_logic;
    signal pc_out    : std_logic_vector(12 downto 0);
      
    signal cnt_inc   : std_logic;
    signal cnt_dec   : std_logic;
    signal cnt_out   : std_logic_vector(7 downto 0);

    -- deklaracia automatu START JE PRIDANY
    type FSMstate is (
        IDLE, 
        INIT, 
        FINISH, 
        FETCH, 
        FETCH2, 
        DECODE, 
        MOVE_RIGHT, 
        MOVE_LEFT, 
        INKREMENT, 
        INKREMENT1, 
        INKREMENT2, 
        DEKREMENT, 
        DEKREMENT1, 
        DEKREMENT2, 
        PRINT, 
        PRINT1, 
        READ, 
        READ1, 
        BEFORE_WHILE_START, 
        WHILE_START, 
        WHILE_START1, 
        WHILE_END, 
        WHILE_END1, 
        WHILE_END2, 
        WHILE_END3
    );

    signal cur_state : FSMstate;
    signal next_state : FSMstate;

begin

-- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
--   - nelze z vice procesu ovladat stejny signal,
--   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
--      - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
--      - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly. 


-- MULTIPLEXOR 1
mx_1: process (CLK, RESET, mx_1_sel) is
    begin 
        if RESET = '1' then
            DATA_ADDR <= (others => '0');
        else
            if mx_1_sel = '0' then
                -- ide do vnutra ptr
                DATA_ADDR <= ptr_out;
            else
                -- ide do vnutra pc
                DATA_ADDR <= pc_out;
            end if;
        end if;
    end process;


-- MULTIPLEXOR 2
mx_2: process (CLK, RESET, mx_2_sel) is
    begin
        if RESET = '1' then
            DATA_WDATA <= (others => '0');
        elsif (rising_edge(CLK)) then
            if mx_2_sel = "00" then
                DATA_WDATA <= IN_DATA;
            elsif mx_2_sel = "01" then
                DATA_WDATA <= DATA_RDATA - 1;
            elsif mx_2_sel = "11" then
                DATA_WDATA <= DATA_RDATA + 1;
            else
                DATA_WDATA <= (others => '0');
            end if;
        end if;
    end process;


-- PTR REGISTER/UKAZATEL
ptr_register: process (RESET, CLK, ptr_inc, ptr_dec) is 
    begin
        if RESET = '1' then
            ptr_out <= (others => '0');
        elsif rising_edge(CLK) then
            if ptr_inc = '1' then
                -- keby pretiekol buffer
                if (ptr_out = x"1FFF") then
                    ptr_out <= (others => '0');
                else 
                    ptr_out <= ptr_out + 1;
                end if;
            elsif ptr_dec = '1' then
                -- keby pretiekol buffer
                if (ptr_out = x"0000") then
                    ptr_out <= (others => '1');
                else
                    ptr_out <= ptr_out - 1;
                end if;
            end if;
        end if;
    end process;


-- PC REGISTER/PC COUNTER
pc_register: process (RESET, CLK, pc_inc, pc_dec) is 
    begin
        if RESET = '1' then
            pc_out <= (others => '0');
        elsif rising_edge(CLK) then
            if pc_inc = '1' then
                pc_out <= pc_out + 1;
            elsif pc_dec = '1' then
                pc_out <= pc_out - 1;
            end if;
        end if;
    end process;


-- COUNTER
cnt: process (RESET, CLK, cnt_inc, cnt_dec) is 
    begin
        if RESET = '1' then
            cnt_out <= (others => '0');
        elsif rising_edge(CLK) then
            if cnt_inc = '1' then
                cnt_out <= cnt_out + 1;
            elsif cnt_dec = '1' then
                cnt_out <= cnt_out - 1;
            end if;
        end if;
    end process;

-- FSM state register
state_register: process(CLK, RESET) is
    begin
        if RESET = '1' then
            cur_state <= IDLE;
        elsif CLK'event and CLK = '1' and EN = '1' then
            cur_state <= next_state;
        end if;
    end process;

next_state_logic: process (cur_state, RESET, CLK, DATA_RDATA)
    begin
        -- inicializacia
        DATA_RDWR <= '0';
        DATA_EN <= '1';

        IN_REQ <= '0';
        OUT_WE <= '0';

        mx_1_sel <= '0';
        mx_2_sel <= "00";

        ptr_inc <= '0';
        ptr_dec <= '0';

        pc_inc <= '0';
        pc_dec <= '0';

        DONE <= '0';

        case cur_state is
            -- caka na ENABLE PROCESORU
            when IDLE =>
                READY <= '0';
                if EN = '1' then
                    next_state <= INIT;
                else 
                    next_state <= IDLE;
                end if;
            -- PROCESOR/ptr ukazatel sa inicializuje
            when INIT =>
                ptr_inc <= '1';
                if (DATA_RDATA = x"40") then
                    next_state <= FETCH; 
                else 
                    next_state <= INIT;
                end if;
            when FETCH =>
                mx_1_sel <= '1';
                READY <= '1';
                ptr_dec <= '1';
                next_state <= FETCH2;   
            -- sem sa AUTOMAT vracia, aby sa vykonala dalsia instrukcia            
            when FETCH2 =>
                mx_1_sel <= '1';
                next_state <= DECODE;
            -- dekodovanie instrukcii
            when DECODE =>
                mx_1_sel <= '1';
                case DATA_RDATA is
                    when x"3E" =>
                        next_state <= MOVE_RIGHT;
                    when x"3C" =>
                        next_state <= MOVE_LEFT;
                    when x"2B" =>
                        -- mx_1_sel <= '0';
                        next_state <= INKREMENT;
                    when x"2D" =>
                        -- mx_1_sel <= '0';
                        next_state <= DEKREMENT;
                    when x"2E" =>
                        next_state <= PRINT;
                    when x"2C" =>
                        next_state <= READ;
                    when x"5B" =>
                        next_state <= BEFORE_WHILE_START;
                    when x"5D" =>
                        next_state <= WHILE_END;
                    when x"7E" =>
                        next_state <= WHILE_START1;
                    when x"40" =>
                        next_state <= FINISH;
                    when others =>
                        pc_inc <= '1';
                        next_state <= FETCH2;
                end case;

            -- POSUVY  
            when MOVE_RIGHT =>
                ptr_inc <= '1';
                pc_inc <= '1';
                next_state <= FETCH2;

            when MOVE_LEFT =>
                ptr_dec <= '1';
                pc_inc <= '1';
                next_state <= FETCH2;
            
            -- IKREMENT/DEKREMENT PODLA TOHO AKO PROCESOR CITA BUNKU V PAMATI A PREPISUJE
            when INKREMENT =>
                DATA_RDWR <= '0';
                mx_2_sel <= "11";
                next_state <= INKREMENT1;
            
            when INKREMENT1 =>
                mx_2_sel <= "11";
                pc_inc <= '1';
                next_state <= INKREMENT2;
            
            when INKREMENT2 =>
                DATA_RDWR <= '1';
                mx_2_sel <= "11";
                next_state <= FETCH2;

            when DEKREMENT =>
                DATA_RDWR <= '0';
                next_state <= DEKREMENT1;
            
            when DEKREMENT1 =>
                mx_1_sel <= '0';
                mx_2_sel <= "01";
                pc_inc <= '1';
                next_state <= DEKREMENT2;
            
            when DEKREMENT2 =>
                mx_2_sel <= "00";
                DATA_RDWR <= '1';
                next_state <= FETCH2;
            
            -- PRINT, cez zbernicu sa musi data citat
            when PRINT => 
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                if (OUT_BUSY = '1') then
                    next_state <= PRINT; 
                else 
                    next_state <= PRINT1;
                end if;

            when PRINT1 =>
                mx_1_sel <= '0';
                OUT_WE <= '1';
                OUT_DATA <= DATA_RDATA;
                pc_inc <= '1';
                next_state <= FETCH2;
            
            -- READ, musi byt validny input
            when READ =>
                IN_REQ <= '1';
                if (IN_VLD = '1') then
                    next_state <= READ1; 
                else 
                    next_state <= READ;
                end if;
            
            when READ1 =>
                IN_REQ <= '1';
                mx_2_sel <= "00";
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                pc_inc <= '1';
                next_state <= FETCH2;
            
            -- while cyklus
            when BEFORE_WHILE_START =>  
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                mx_1_sel <= '1';
                next_state <= WHILE_START;
            
            -- ci je koniec while cyklu alebo sa ma vykonat instrukcia vo while
            when WHILE_START =>
                if DATA_RDATA = "00000000" then
                    next_state <= WHILE_START1;
                else
                    pc_inc <= '1';
                    next_state  <= FETCH2;
                end if;
            
            -- koniec while cyklu alebo break
            -- nastavi sa za koniec while cyklu
            when WHILE_START1 =>
                mx_1_sel <= '1';
                DATA_RDWR <= '0';
                if DATA_RDATA = x"5D" then
                    next_state <= FETCH2;
                -- elsif DATA_RDATA = x"7E" then
                --     next_state <= BREAK;
                else
                    pc_inc <= '1';
                    next_state <= WHILE_START1;
                end if;

            -- when BREAK =>
            --     if DATA_RDATA = x"5D" then
            --         pc_inc <= '1';
            --         next_state <= FETCH2;
            --     else
            --         pc_inc <= '1';
            --         next_state <= BREAK;
            --     end if;
            
            -- ] pride a ak while neskoncil tak ide na zaciatok while cyklu
            -- inak ide vykonavat instrukciu za while cyklom
            when WHILE_END =>
                if DATA_RDATA = "00000000" then
                    pc_inc <= '1';
                    next_state <= FETCH2;
                else
                    next_state  <= WHILE_END1;
                end if;
            
            -- dostavanie sa na zaciatok while cyklu
            when WHILE_END1 =>
                mx_1_sel <= '1';
                DATA_RDWR <= '0';
                if DATA_RDATA = x"5B" then
                    next_state <= WHILE_END2;
                else
                    pc_dec <= '1';
                    next_state <= WHILE_END1;
                end if;
            
            -- tieto dva stavy su aby zacatie dalsej iteracie while cyklu fungovalo s CLK
            -- a aby tam boli spravne veci nastavene
            when WHILE_END2 =>
                mx_1_sel <= '0';
                next_state <= WHILE_END3;

            when WHILE_END3 =>
                next_state <= WHILE_START;
            
            -- koniec programu
            when FINISH =>
                READY <= '1';
                DONE <= '1';
        end case;

    end process;
    
end behavioral;

