extends RefCounted
const TITLES=["First Signal","Pocket Lights","Little Satellites","Neon Guardian","Amber Breath","Crystal Bridge","Crossing Signals","Prism Sentinel","Swing Skyline","Electric Steps","Glass Tempest","Perfect Sky"]
const LINES=[
	["멈춰 버린 도시에서 작은 신호가 들려왔다.","루미: 첫 박자를 켜 줘. 도시가 널 기다려!"],
	["빛이 돌아왔지만 골목의 리듬은 끊겨 있다.","루미: 쉬는 박자까지 들으면 길이 보여."],
	["흩어진 위성들이 짧은 신호를 주고받는다.","루미: 두 번의 반짝임을 놓치지 마!"],
	["네온 수호자가 첫 번째 관문을 막아섰다.","루미: 네 비트로 수호자를 깨워 줘!"],
	["호박빛 정원에 긴 선율이 숨 쉬고 있다.","루미: 빛이 끝날 때까지 손을 놓지 마."],
	["수정 다리는 오직 음악에만 반응한다.","루미: 긴 음을 이어 다리를 완성하자."],
	["서로 다른 신호가 교차로에서 만났다.","루미: 짧은 빛과 긴 빛을 이어 줘!"],
	["프리즘 파수꾼이 두 번째 문을 시험한다.","루미: 멜로디의 시작과 끝을 기억해!"],
	["도시의 높은 곳에서 새로운 그루브가 울린다.","루미: 박자 사이의 신호도 들어 봐."],
	["빛의 기차가 점점 속도를 높이고 있다.","루미: 힘을 빼고 한 음씩 따라가자."],
	["유리 폭풍 속에 마지막 좌표가 숨어 있다.","루미: 폭풍이 몰아쳐도 선율은 이어져!"],
	["모든 신호가 하늘의 무대에서 하나가 된다.","루미: 마지막 곡이야. 우리의 리듬을 들려줘!"]]
static func index(id: String) -> int:return clampi(int(id.substr(1))-1,0,11)
static func title(id: String) -> String:return TITLES[index(id)]
static func intro(id: String) -> Array:return LINES[index(id)]
static func ending(id: String) -> String:
	return "도시에 음악이 돌아왔다! 루미와의 첫 여정 완료." if id=="m12" else "수호자가 깨어났어! 다음 구역으로 가자." if int(id.substr(1))%4==0 else "신호 복구 완료! 다음 선율이 널 기다려."
