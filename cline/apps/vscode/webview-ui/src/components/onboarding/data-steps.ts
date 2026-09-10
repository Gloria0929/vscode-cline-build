export enum NEW_USER_TYPE {
	CLINE_PASS = "cline-pass",
	FREE = "free",
	POWER = "power",
	BYOK = "byok",
}

type UserTypeSelection = {
	title: string
	description: string
	type: NEW_USER_TYPE
	learnMoreUrl?: string
}

export const STEP_CONFIG = {
	0: {
		title: "How will you use Coder?",
		description: "在下方选择一个选项以开始。",
		buttons: [{ text: "继续", action: "next", variant: "default" }],
	},
	[NEW_USER_TYPE.CLINE_PASS]: {
		title: "Select a ClinePass model",
		buttons: [
			{ text: "Create my Account", action: "signup", variant: "default" },
			{ text: "返回", action: "back", variant: "secondary" },
		],
	},
	[NEW_USER_TYPE.FREE]: {
		title: "Select a free model",
		buttons: [
			{ text: "Create my Account", action: "signup", variant: "default" },
			{ text: "返回", action: "back", variant: "secondary" },
		],
	},
	[NEW_USER_TYPE.POWER]: {
		title: "选择你的模型",
		buttons: [
			{ text: "Create my Account", action: "signup", variant: "default" },
			{ text: "返回", action: "back", variant: "secondary" },
		],
	},
	[NEW_USER_TYPE.BYOK]: {
		title: "配置你的服务商",
		buttons: [
			{ text: "继续", action: "done", variant: "default" },
			{ text: "返回", action: "back", variant: "secondary" },
		],
	},
	2: {
		title: "即将完成！",
		description: "Complete account creation in your browser. Then come back here to finish up.",
		buttons: [{ text: "返回", action: "back", variant: "secondary" }],
	},
} as const

// Self-hosted build: only the "使用自己的 API 密钥" path is offered.
const BASE_USER_TYPE_SELECTIONS: UserTypeSelection[] = [
	{ title: "使用自己的 API 密钥", description: "Use Coder with your provider of choice", type: NEW_USER_TYPE.BYOK },
]

export function getUserTypeSelections(_hasClinePassModels: boolean): UserTypeSelection[] {
	return BASE_USER_TYPE_SELECTIONS
}
