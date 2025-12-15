import asyncio
import json
import random
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from typing import Dict, List, Set, Tuple, Optional
import websockets
from aiohttp import web
import aiohttp

# 游戏配置
GAME_WIDTH = 600
GAME_HEIGHT = 400
GRID_SIZE = 20
GRID_WIDTH = GAME_WIDTH // GRID_SIZE
GRID_HEIGHT = GAME_HEIGHT // GRID_SIZE
MAX_PLAYERS = 10
INITIAL_SPEED = 10  # 格子/秒
FOOD_COUNT = 5
SPEED_INCREMENT = 0.5  # 每吃一个食物增加的速度

# 方向向量
DIRECTIONS = {
    "up": (0, -1),
    "down": (0, 1),
    "left": (-1, 0),
    "right": (1, 0)
}

@dataclass
class Player:
    """玩家类"""
    id: str
    name: str
    color: str
    direction: Tuple[int, int] = (1, 0)
    next_direction: Optional[Tuple[int, int]] = None
    body: List[Tuple[int, int]] = field(default_factory=list)
    score: int = 0
    alive: bool = True
    ws: Optional[websockets.WebSocketServerProtocol] = None
    last_move_time: float = 0.0
    
    def __post_init__(self):
        # 随机初始位置
        x = random.randint(5, GRID_WIDTH - 6)
        y = random.randint(5, GRID_HEIGHT - 6)
        self.body = [(x, y), (x-1, y), (x-2, y)]
        self.last_move_time = asyncio.get_event_loop().time()

@dataclass
class Food:
    """食物类"""
    x: int
    y: int
    id: str = field(default_factory=lambda: str(uuid.uuid4()))

class Game:
    """游戏类"""
    def __init__(self):
        self.players: Dict[str, Player] = {}
        self.foods: List[Food] = []
        self.game_loop_task: Optional[asyncio.Task] = None
        self.last_update_time = 0
        self.speed = INITIAL_SPEED
        
    def add_player(self, player_id: str, name: str, ws) -> Player:
        """添加玩家到游戏"""
        colors = [
            "#FF5252", "#FF4081", "#E040FB", "#7C4DFF", "#536DFE",
            "#448AFF", "#40C4FF", "#18FFFF", "#64FFDA", "#69F0AE"
        ]
        
        color = colors[len(self.players) % len(colors)]
        player = Player(id=player_id, name=name, color=color, ws=ws)
        self.players[player_id] = player
        return player
    
    def remove_player(self, player_id: str):
        """从游戏中移除玩家"""
        if player_id in self.players:
            del self.players[player_id]
    
    def generate_food(self):
        """生成食物"""
        while len(self.foods) < FOOD_COUNT:
            # 查找所有被占用的位置
            occupied = set()
            for player in self.players.values():
                occupied.update(player.body)
            for food in self.foods:
                occupied.add((food.x, food.y))
            
            # 生成不在占用位置的食物
            attempts = 0
            while attempts < 100:  # 防止无限循环
                x = random.randint(0, GRID_WIDTH - 1)
                y = random.randint(0, GRID_HEIGHT - 1)
                if (x, y) not in occupied:
                    self.foods.append(Food(x, y))
                    break
                attempts += 1
    
    def update(self):
        """更新游戏状态"""
        current_time = asyncio.get_event_loop().time()
        time_since_last_update = current_time - self.last_update_time
        
        # 控制更新频率
        if time_since_last_update < 1.0 / self.speed:
            return
        
        self.last_update_time = current_time
        
        # 更新每个玩家的方向
        for player in self.players.values():
            if player.next_direction and player.alive:
                # 防止直接反向移动
                current_dx, current_dy = player.direction
                next_dx, next_dy = player.next_direction
                if (current_dx, current_dy) != (-next_dx, -next_dy):
                    player.direction = player.next_direction
                player.next_direction = None
        
        # 移动每个玩家
        for player in self.players.values():
            if not player.alive:
                continue
                
            dx, dy = player.direction
            head_x, head_y = player.body[0]
            new_x = (head_x + dx) % GRID_WIDTH
            new_y = (head_y + dy) % GRID_HEIGHT
            new_head = (new_x, new_y)
            
            # 检查是否撞到自己
            if new_head in player.body[1:]:
                player.alive = False
                continue
            
            # 检查是否撞到其他玩家
            collision = False
            for other_player in self.players.values():
                if other_player.id != player.id and other_player.alive:
                    if new_head in other_player.body:
                        collision = True
                        break
            if collision:
                player.alive = False
                continue
            
            # 移动蛇
            player.body.insert(0, new_head)
            
            # 检查是否吃到食物
            food_eaten = None
            for i, food in enumerate(self.foods):
                if (new_head[0], new_head[1]) == (food.x, food.y):
                    food_eaten = i
                    player.score += 10
                    self.speed += SPEED_INCREMENT
                    break
            
            if food_eaten is not None:
                # 吃到食物，不移除尾部
                self.foods.pop(food_eaten)
            else:
                # 没吃到食物，移除尾部
                player.body.pop()
    
    def get_state(self):
        """获取游戏状态"""
        players_data = []
        for player in self.players.values():
            players_data.append({
                "id": player.id,
                "name": player.name,
                "color": player.color,
                "body": player.body,
                "score": player.score,
                "alive": player.alive
            })
        
        foods_data = [{"x": food.x, "y": food.y, "id": food.id} for food in self.foods]
        
        return {
            "players": players_data,
            "foods": foods_data,
            "grid_width": GRID_WIDTH,
            "grid_height": GRID_HEIGHT,
            "speed": self.speed
        }

# 全局游戏实例
game = Game()

async def game_loop():
    """游戏主循环"""
    while True:
        try:
            # 生成食物
            game.generate_food()
            
            # 更新游戏状态
            game.update()
            
            # 广播游戏状态给所有连接的客户端
            state = game.get_state()
            state_json = json.dumps({
                "type": "game_state",
                "data": state
            })
            
            # 发送给所有连接的玩家
            tasks = []
            for player in list(game.players.values()):
                if player.ws and not player.ws.closed:
                    try:
                        tasks.append(player.ws.send(state_json))
                    except:
                        pass
            
            if tasks:
                await asyncio.gather(*tasks, return_exceptions=True)
            
            # 清理死亡玩家
            dead_players = []
            for player_id, player in list(game.players.items()):
                if not player.alive and player.ws and player.ws.closed:
                    dead_players.append(player_id)
            
            for player_id in dead_players:
                game.remove_player(player_id)
            
            await asyncio.sleep(0.05)  # 控制游戏循环频率
            
        except Exception as e:
            print(f"Game loop error: {e}")
            await asyncio.sleep(1)

async def handle_websocket(request):
    """处理WebSocket连接"""
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    
    player_id = None
    player_name = f"Player{random.randint(1000, 9999)}"
    
    try:
        async for msg in ws:
            if msg.type == web.WSMsgType.TEXT:
                data = json.loads(msg.data)
                
                if data["type"] == "join":
                    # 玩家加入游戏
                    player_id = data.get("player_id", str(uuid.uuid4()))
                    player_name = data.get("name", player_name)
                    
                    # 检查玩家数量
                    if len(game.players) >= MAX_PLAYERS:
                        await ws.send(json.dumps({
                            "type": "error",
                            "message": "游戏已满，最多10人"
                        }))
                        await ws.close()
                        return
                    
                    # 添加玩家
                    player = game.add_player(player_id, player_name, ws)
                    
                    # 发送欢迎消息
                    await ws.send(json.dumps({
                        "type": "welcome",
                        "player_id": player_id,
                        "name": player_name,
                        "color": player.color,
                        "grid_size": GRID_SIZE,
                        "game_width": GAME_WIDTH,
                        "game_height": GAME_HEIGHT
                    }))
                    
                    print(f"玩家 {player_name} 加入了游戏")
                
                elif data["type"] == "change_direction":
                    # 改变方向
                    if player_id and player_id in game.players:
                        direction = data["direction"]
                        if direction in DIRECTIONS:
                            game.players[player_id].next_direction = DIRECTIONS[direction]
                
                elif data["type"] == "chat":
                    # 聊天消息
                    if player_id and player_id in game.players:
                        message = data.get("message", "")
                        # 广播聊天消息
                        chat_data = json.dumps({
                            "type": "chat",
                            "player": player_name,
                            "message": message,
                            "time": datetime.now().strftime("%H:%M:%S")
                        })
                        
                        tasks = []
                        for p in list(game.players.values()):
                            if p.ws and not p.ws.closed:
                                try:
                                    tasks.append(p.ws.send(chat_data))
                                except:
                                    pass
                        
                        if tasks:
                            await asyncio.gather(*tasks, return_exceptions=True)
    
    except Exception as e:
        print(f"WebSocket error: {e}")
    finally:
        # 清理玩家
        if player_id:
            game.remove_player(player_id)
            print(f"玩家 {player_name} 离开了游戏")
    
    return ws

async def index_handler(request):
    """处理主页请求"""
    with open("index.html", "r", encoding="utf-8") as f:
        html_content = f.read()
    
    return web.Response(text=html_content, content_type="text/html")

async def get_players_handler(request):
    """获取当前玩家列表"""
    players = []
    for player in game.players.values():
        players.append({
            "id": player.id,
            "name": player.name,
            "score": player.score,
            "alive": player.alive
        })
    
    return web.Response(text=json.dumps({"players": players}), content_type="application/json")

async def main():
    """主函数"""
    # 启动游戏循环
    asyncio.create_task(game_loop())
    
    # 创建HTTP服务器
    app = web.Application()
    app.router.add_get('/', index_handler)
    app.router.add_get('/ws', handle_websocket)
    app.router.add_get('/players', get_players_handler)
    
    # 添加静态文件路由
    app.router.add_static('/static/', path='./static', name='static')
    
    # 创建HTML文件
    html_content = """
    <!DOCTYPE html>
    <html lang="zh-CN">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>多人贪吃蛇游戏</title>
        <style>
            * {
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }
            
            body {
                font-family: 'Arial', sans-serif;
                background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
                color: #fff;
                min-height: 100vh;
                padding: 20px;
            }
            
            .container {
                max-width: 1000px;
                margin: 0 auto;
                padding: 20px;
            }
            
            header {
                text-align: center;
                margin-bottom: 20px;
            }
            
            h1 {
                font-size: 2.5rem;
                color: #4dff91;
                text-shadow: 0 0 10px rgba(77, 255, 145, 0.5);
                margin-bottom: 10px;
            }
            
            .subtitle {
                color: #a0a0c0;
                font-size: 1.1rem;
                margin-bottom: 20px;
            }
            
            .game-container {
                display: flex;
                flex-wrap: wrap;
                gap: 20px;
                margin-bottom: 20px;
            }
            
            .game-area {
                flex: 1;
                min-width: 300px;
            }
            
            .game-ui {
                flex: 0 0 300px;
                background: rgba(0, 0, 0, 0.3);
                border-radius: 10px;
                padding: 20px;
                border: 1px solid #333;
            }
            
            #gameCanvas {
                background-color: #0d1b2a;
                border-radius: 10px;
                border: 2px solid #333;
                display: block;
                margin: 0 auto;
            }
            
            .panel {
                margin-bottom: 20px;
            }
            
            .panel h2 {
                color: #4dff91;
                border-bottom: 2px solid #4dff91;
                padding-bottom: 5px;
                margin-bottom: 15px;
                font-size: 1.3rem;
            }
            
            .player-list {
                list-style: none;
                max-height: 200px;
                overflow-y: auto;
            }
            
            .player-item {
                display: flex;
                justify-content: space-between;
                padding: 8px 10px;
                background: rgba(255, 255, 255, 0.05);
                border-radius: 5px;
                margin-bottom: 5px;
                border-left: 4px solid #4dff91;
            }
            
            .player-name {
                font-weight: bold;
            }
            
            .player-score {
                color: #ffd700;
            }
            
            .controls {
                margin-top: 20px;
            }
            
            .control-info {
                background: rgba(0, 0, 0, 0.2);
                padding: 15px;
                border-radius: 5px;
                margin-bottom: 15px;
            }
            
            .control-info p {
                margin-bottom: 5px;
                color: #a0a0c0;
            }
            
            .chat-container {
                margin-top: 20px;
            }
            
            #chatLog {
                height: 150px;
                overflow-y: auto;
                background: rgba(0, 0, 0, 0.2);
                border-radius: 5px;
                padding: 10px;
                margin-bottom: 10px;
                border: 1px solid #333;
            }
            
            .chat-message {
                margin-bottom: 5px;
                padding: 5px;
                border-radius: 3px;
                background: rgba(255, 255, 255, 0.05);
            }
            
            .chat-input {
                display: flex;
                gap: 10px;
            }
            
            #chatInput {
                flex: 1;
                padding: 10px;
                border-radius: 5px;
                border: 1px solid #333;
                background: rgba(0, 0, 0, 0.3);
                color: white;
            }
            
            button {
                padding: 10px 20px;
                background: linear-gradient(135deg, #4dff91 0%, #1a8cff 100%);
                border: none;
                border-radius: 5px;
                color: white;
                font-weight: bold;
                cursor: pointer;
                transition: all 0.3s;
            }
            
            button:hover {
                transform: translateY(-2px);
                box-shadow: 0 5px 15px rgba(77, 255, 145, 0.4);
            }
            
            button:active {
                transform: translateY(0);
            }
            
            .instructions {
                background: rgba(0, 0, 0, 0.2);
                padding: 20px;
                border-radius: 10px;
                margin-top: 20px;
                border: 1px solid #333;
            }
            
            .instructions h3 {
                color: #4dff91;
                margin-bottom: 10px;
            }
            
            .instructions ul {
                padding-left: 20px;
                color: #a0a0c0;
            }
            
            .instructions li {
                margin-bottom: 5px;
            }
            
            .status {
                text-align: center;
                margin-bottom: 15px;
                padding: 10px;
                border-radius: 5px;
                background: rgba(0, 0, 0, 0.2);
            }
            
            .status.connected {
                color: #4dff91;
                border: 1px solid #4dff91;
            }
            
            .status.disconnected {
                color: #ff5252;
                border: 1px solid #ff5252;
            }
            
            .game-stats {
                display: flex;
                justify-content: space-between;
                margin-bottom: 15px;
                padding: 10px;
                background: rgba(0, 0, 0, 0.2);
                border-radius: 5px;
            }
            
            .stat-item {
                text-align: center;
            }
            
            .stat-value {
                font-size: 1.5rem;
                font-weight: bold;
                color: #4dff91;
            }
            
            .stat-label {
                font-size: 0.9rem;
                color: #a0a0c0;
            }
            
            @media (max-width: 768px) {
                .game-container {
                    flex-direction: column;
                }
                
                .game-ui {
                    width: 100%;
                }
            }
        </style>
    </head>
    <body>
        <div class="container">
            <header>
                <h1>🐍 多人贪吃蛇</h1>
                <p class="subtitle">最多10人同时游戏 | 使用方向键或WASD控制</p>
            </header>
            
            <div class="game-container">
                <div class="game-area">
                    <div class="status disconnected" id="status">正在连接服务器...</div>
                    <canvas id="gameCanvas" width="600" height="400"></canvas>
                    
                    <div class="game-stats">
                        <div class="stat-item">
                            <div class="stat-value" id="playerCount">0</div>
                            <div class="stat-label">在线玩家</div>
                        </div>
                        <div class="stat-item">
                            <div class="stat-value" id="playerScore">0</div>
                            <div class="stat-label">你的分数</div>
                        </div>
                        <div class="stat-item">
                            <div class="stat-value" id="gameSpeed">10</div>
                            <div class="stat-label">游戏速度</div>
                        </div>
                    </div>
                </div>
                
                <div class="game-ui">
                    <div class="panel">
                        <h2>玩家列表 (最多10人)</h2>
                        <ul class="player-list" id="playerList">
                            <li class="player-item">等待玩家加入...</li>
                        </ul>
                    </div>
                    
                    <div class="controls">
                        <div class="control-info">
                            <p><strong>控制方式:</strong></p>
                            <p>↑↓←→ 或 WASD 键控制方向</p>
                            <p>空格键暂停/继续聊天</p>
                        </div>
                        
                        <div class="chat-container">
                            <h2>游戏聊天</h2>
                            <div id="chatLog"></div>
                            <div class="chat-input">
                                <input type="text" id="chatInput" placeholder="输入消息..." maxlength="100">
                                <button id="sendBtn">发送</button>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="instructions">
                <h3>游戏说明</h3>
                <ul>
                    <li>使用方向键或WASD键控制你的蛇移动</li>
                    <li>吃掉红色食物可以增加长度和分数</li>
                    <li>撞到自己或其他玩家会导致死亡</li>
                    <li>游戏支持最多10人同时游玩</li>
                    <li>游戏速度会随着玩家吃掉食物而增加</li>
                    <li>蛇可以穿过边界到达另一侧</li>
                </ul>
            </div>
        </div>
        
        <script>
            // 游戏变量
            let playerId = null;
            let playerColor = "#FF5252";
            let playerName = "Player" + Math.floor(1000 + Math.random() * 9000);
            let ws = null;
            let gamePaused = false;
            
            // 获取DOM元素
            const canvas = document.getElementById('gameCanvas');
            const ctx = canvas.getContext('2d');
            const statusEl = document.getElementById('status');
            const playerListEl = document.getElementById('playerList');
            const playerCountEl = document.getElementById('playerCount');
            const playerScoreEl = document.getElementById('playerScore');
            const gameSpeedEl = document.getElementById('gameSpeed');
            const chatLogEl = document.getElementById('chatLog');
            const chatInputEl = document.getElementById('chatInput');
            const sendBtn = document.getElementById('sendBtn');
            
            // 初始化WebSocket连接
            function connectWebSocket() {
                const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
                const wsUrl = `${protocol}//${window.location.host}/ws`;
                
                ws = new WebSocket(wsUrl);
                
                ws.onopen = function() {
                    console.log('已连接到服务器');
                    statusEl.textContent = '已连接到服务器';
                    statusEl.className = 'status connected';
                    
                    // 发送加入游戏消息
                    ws.send(JSON.stringify({
                        type: 'join',
                        player_id: localStorage.getItem('snakePlayerId') || generatePlayerId(),
                        name: localStorage.getItem('snakePlayerName') || playerName
                    }));
                };
                
                ws.onmessage = function(event) {
                    const data = JSON.parse(event.data);
                    
                    switch(data.type) {
                        case 'welcome':
                            playerId = data.player_id;
                            playerColor = data.color;
                            playerName = data.name;
                            
                            // 保存到本地存储
                            localStorage.setItem('snakePlayerId', playerId);
                            localStorage.setItem('snakePlayerName', playerName);
                            
                            console.log(`欢迎，${playerName} (${playerId})`);
                            break;
                            
                        case 'game_state':
                            updateGame(data.data);
                            break;
                            
                        case 'chat':
                            addChatMessage(data.player, data.message, data.time);
                            break;
                            
                        case 'error':
                            alert(data.message);
                            break;
                    }
                };
                
                ws.onclose = function() {
                    console.log('与服务器的连接已断开');
                    statusEl.textContent = '与服务器连接已断开，5秒后重连...';
                    statusEl.className = 'status disconnected';
                    
                    // 5秒后重连
                    setTimeout(connectWebSocket, 5000);
                };
                
                ws.onerror = function(error) {
                    console.error('WebSocket错误:', error);
                    statusEl.textContent = '连接错误，请检查网络';
                    statusEl.className = 'status disconnected';
                };
            }
            
            // 生成玩家ID
            function generatePlayerId() {
                return 'player_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
            }
            
            // 更新游戏状态
            function updateGame(state) {
                // 清除画布
                ctx.fillStyle = '#0d1b2a';
                ctx.fillRect(0, 0, canvas.width, canvas.height);
                
                // 绘制网格
                ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
                ctx.lineWidth = 1;
                
                for (let x = 0; x <= 600; x += 20) {
                    ctx.beginPath();
                    ctx.moveTo(x, 0);
                    ctx.lineTo(x, 400);
                    ctx.stroke();
                }
                
                for (let y = 0; y <= 400; y += 20) {
                    ctx.beginPath();
                    ctx.moveTo(0, y);
                    ctx.lineTo(600, y);
                    ctx.stroke();
                }
                
                // 绘制食物
                ctx.fillStyle = '#FF5252';
                for (const food of state.foods) {
                    ctx.beginPath();
                    ctx.arc(
                        food.x * 20 + 10,
                        food.y * 20 + 10,
                        8, 0, Math.PI * 2
                    );
                    ctx.fill();
                    
                    // 食物光泽效果
                    ctx.fillStyle = 'rgba(255, 255, 255, 0.3)';
                    ctx.beginPath();
                    ctx.arc(
                        food.x * 20 + 6,
                        food.y * 20 + 6,
                        3, 0, Math.PI * 2
                    );
                    ctx.fill();
                    ctx.fillStyle = '#FF5252';
                }
                
                // 绘制玩家
                let myPlayer = null;
                let alivePlayers = 0;
                
                for (const player of state.players) {
                    if (player.id === playerId) {
                        myPlayer = player;
                    }
                    
                    if (player.alive) {
                        alivePlayers++;
                    }
                    
                    // 绘制蛇身
                    ctx.fillStyle = player.color;
                    for (let i = 0; i < player.body.length; i++) {
                        const [x, y] = player.body[i];
                        
                        // 蛇头
                        if (i === 0) {
                            ctx.fillRect(x * 20, y * 20, 20, 20);
                            
                            // 蛇头眼睛
                            ctx.fillStyle = 'white';
                            ctx.beginPath();
                            
                            // 根据方向确定眼睛位置
                            let eye1X, eye1Y, eye2X, eye2Y;
                            if (player.body.length > 1) {
                                const [headX, headY] = player.body[0];
                                const [nextX, nextY] = player.body[1];
                                
                                if (nextX < headX) { // 向右移动
                                    eye1X = x * 20 + 15; eye1Y = y * 20 + 5;
                                    eye2X = x * 20 + 15; eye2Y = y * 20 + 15;
                                } else if (nextX > headX) { // 向左移动
                                    eye1X = x * 20 + 5; eye1Y = y * 20 + 5;
                                    eye2X = x * 20 + 5; eye2Y = y * 20 + 15;
                                } else if (nextY < headY) { // 向下移动
                                    eye1X = x * 20 + 5; eye1Y = y * 20 + 15;
                                    eye2X = x * 20 + 15; eye2Y = y * 20 + 15;
                                } else { // 向上移动
                                    eye1X = x * 20 + 5; eye1Y = y * 20 + 5;
                                    eye2X = x * 20 + 15; eye2Y = y * 20 + 5;
                                }
                            } else {
                                eye1X = x * 20 + 5; eye1Y = y * 20 + 5;
                                eye2X = x * 20 + 15; eye2Y = y * 20 + 5;
                            }
                            
                            ctx.arc(eye1X, eye1Y, 2, 0, Math.PI * 2);
                            ctx.arc(eye2X, eye2Y, 2, 0, Math.PI * 2);
                            ctx.fill();
                            
                            // 蛇瞳孔
                            ctx.fillStyle = 'black';
                            ctx.beginPath();
                            ctx.arc(eye1X, eye1Y, 1, 0, Math.PI * 2);
                            ctx.arc(eye2X, eye2Y, 1, 0, Math.PI * 2);
                            ctx.fill();
                            
                            ctx.fillStyle = player.color;
                        } else {
                            // 蛇身
                            ctx.fillRect(x * 20, y * 20, 20, 20);
                            
                            // 蛇身内部阴影
                            ctx.fillStyle = 'rgba(255, 255, 255, 0.2)';
                            ctx.fillRect(x * 20 + 2, y * 20 + 2, 16, 16);
                            ctx.fillStyle = player.color;
                        }
                    }
                    
                    // 绘制玩家名称
                    if (player.body.length > 0) {
                        const [headX, headY] = player.body[0];
                        ctx.fillStyle = 'white';
                        ctx.font = '12px Arial';
                        ctx.textAlign = 'center';
                        ctx.fillText(
                            player.name,
                            headX * 20 + 10,
                            headY * 20 - 5
                        );
                    }
                }
                
                // 更新玩家列表
                updatePlayerList(state.players);
                
                // 更新统计信息
                playerCountEl.textContent = `${alivePlayers}/${state.players.length}`;
                gameSpeedEl.textContent = state.speed.toFixed(1);
                
                if (myPlayer) {
                    playerScoreEl.textContent = myPlayer.score;
                    
                    // 如果玩家死亡，显示死亡信息
                    if (!myPlayer.alive) {
                        ctx.fillStyle = 'rgba(0, 0, 0, 0.7)';
                        ctx.fillRect(0, 0, canvas.width, canvas.height);
                        
                        ctx.fillStyle = 'white';
                        ctx.font = 'bold 30px Arial';
                        ctx.textAlign = 'center';
                        ctx.fillText('游戏结束!', canvas.width / 2, canvas.height / 2 - 30);
                        
                        ctx.font = '20px Arial';
                        ctx.fillText(`最终得分: ${myPlayer.score}`, canvas.width / 2, canvas.height / 2 + 20);
                        
                        ctx.font = '16px Arial';
                        ctx.fillText('刷新页面重新开始', canvas.width / 2, canvas.height / 2 + 60);
                    }
                }
            }
            
            // 更新玩家列表
            function updatePlayerList(players) {
                playerListEl.innerHTML = '';
                
                // 按分数排序
                const sortedPlayers = [...players].sort((a, b) => b.score - a.score);
                
                sortedPlayers.forEach(player => {
                    const li = document.createElement('li');
                    li.className = 'player-item';
                    li.style.borderLeftColor = player.color;
                    
                    if (!player.alive) {
                        li.style.opacity = '0.6';
                    }
                    
                    const nameSpan = document.createElement('span');
                    nameSpan.className = 'player-name';
                    nameSpan.textContent = player.name + (player.id === playerId ? ' (你)' : '');
                    
                    const scoreSpan = document.createElement('span');
                    scoreSpan.className = 'player-score';
                    scoreSpan.textContent = player.score;
                    
                    li.appendChild(nameSpan);
                    li.appendChild(scoreSpan);
                    playerListEl.appendChild(li);
                });
            }
            
            // 添加聊天消息
            function addChatMessage(player, message, time) {
                const messageEl = document.createElement('div');
                messageEl.className = 'chat-message';
                messageEl.innerHTML = `<strong style="color: ${player === playerName ? playerColor : '#4dff91'}">${player}:</strong> ${message} <span style="color: #888; font-size: 0.8em;">${time}</span>`;
                
                chatLogEl.appendChild(messageEl);
                chatLogEl.scrollTop = chatLogEl.scrollHeight;
            }
            
            // 发送聊天消息
            function sendChatMessage() {
                const message = chatInputEl.value.trim();
                if (message && ws && ws.readyState === WebSocket.OPEN) {
                    ws.send(JSON.stringify({
                        type: 'chat',
                        message: message
                    }));
                    
                    chatInputEl.value = '';
                }
            }
            
            // 键盘控制
            const keyMap = {
                'ArrowUp': 'up',
                'ArrowDown': 'down',
                'ArrowLeft': 'left',
                'ArrowRight': 'right',
                'w': 'up',
                's': 'down',
                'a': 'left',
                'd': 'right',
                'W': 'up',
                'S': 'down',
                'A': 'left',
                'D': 'right'
            };
            
            document.addEventListener('keydown', (e) => {
                // 如果聊天框有焦点，不处理方向键
                if (document.activeElement === chatInputEl) {
                    if (e.key === 'Enter') {
                        sendChatMessage();
                        e.preventDefault();
                    }
                    return;
                }
                
                // 空格键切换聊天框焦点
                if (e.key === ' ') {
                    e.preventDefault();
                    if (chatInputEl === document.activeElement) {
                        chatInputEl.blur();
                    } else {
                        chatInputEl.focus();
                    }
                    return;
                }
                
                // 方向控制
                if (keyMap[e.key] && ws && ws.readyState === WebSocket.OPEN) {
                    ws.send(JSON.stringify({
                        type: 'change_direction',
                        direction: keyMap[e.key]
                    }));
                    e.preventDefault();
                }
            });
            
            // 发送按钮事件
            sendBtn.addEventListener('click', sendChatMessage);
            chatInputEl.addEventListener('keypress', (e) => {
                if (e.key === 'Enter') {
                    sendChatMessage();
                }
            });
            
            // 触摸控制（移动设备）
            let touchStartX = 0;
            let touchStartY = 0;
            
            canvas.addEventListener('touchstart', (e) => {
                e.preventDefault();
                touchStartX = e.touches[0].clientX;
                touchStartY = e.touches[0].clientY;
            }, {passive: false});
            
            canvas.addEventListener('touchend', (e) => {
                e.preventDefault();
                const touchEndX = e.changedTouches[0].clientX;
                const touchEndY = e.changedTouches[0].clientY;
                
                const dx = touchEndX - touchStartX;
                const dy = touchEndY - touchStartY;
                
                // 确定滑动方向
                if (Math.abs(dx) > Math.abs(dy)) {
                    // 水平滑动
                    if (dx > 0 && ws) {
                        ws.send(JSON.stringify({type: 'change_direction', direction: 'right'}));
                    } else if (dx < 0 && ws) {
                        ws.send(JSON.stringify({type: 'change_direction', direction: 'left'}));
                    }
                } else {
                    // 垂直滑动
                    if (dy > 0 && ws) {
                        ws.send(JSON.stringify({type: 'change_direction', direction: 'down'}));
                    } else if (dy < 0 && ws) {
                        ws.send(JSON.stringify({type: 'change_direction', direction: 'up'}));
                    }
                }
            }, {passive: false});
            
            // 防止触摸滚动
            document.addEventListener('touchmove', (e) => {
                if (e.target === canvas) {
                    e.preventDefault();
                }
            }, {passive: false});
            
            // 初始连接
            connectWebSocket();
            
            // 页面可见性变化处理
            document.addEventListener('visibilitychange', () => {
                if (document.hidden) {
                    console.log('页面切换到后台');
                } else {
                    console.log('页面回到前台');
                }
            });
        </script>
    </body>
    </html>
    """
    
    # 保存HTML文件
    with open("index.html", "w", encoding="utf-8") as f:
        f.write(html_content)
    
    # 创建静态目录
    import os
    if not os.path.exists("static"):
        os.makedirs("static")
    
    # 启动服务器
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, '0.0.0.0', 8001)
    await site.start()
    
    print("多人贪吃蛇游戏服务器已启动！")
    print(f"请访问: http://localhost:8001")
    print(f"最多支持 {MAX_PLAYERS} 人同时游戏")
    
    # 保持服务器运行
    await asyncio.Event().wait()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("服务器已关闭")

