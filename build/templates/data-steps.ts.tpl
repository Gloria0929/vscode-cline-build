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
		title: "How will you use AI Coder?",
		description: "Select an option below to get started.",
		buttons: [{ text: "Continue", action: "next", variant: "default" }],
	},
	[NEW_USER_TYPE.CLINE_PASS]: {
		title: "Select a ClinePass model",
		buttons: [
			{ text: "Create my Account", action: "signup", variant: "default" },
			{ text: "Back", action: "back", variant: "secondary" },
		],
	},
	[NEW_USER_TYPE.FREE]: {
		title: "Select a free model",
		buttons: [
			{ text: "Create my Account", action: "signup", variant: "default" },
			{ text: "Back", action: "back", variant: "secondary" },
		],
	},
	[NEW_USER_TYPE.POWER]: {
		title: "Select your model",
		buttons: [
			{ text: "Create my Account", action: "signup", variant: "default" },
			{ text: "Back", action: "back", variant: "secondary" },
		],
	},
	[NEW_USER_TYPE.BYOK]: {
		title: "Configure your provider",
		buttons: [
			{ text: "Continue", action: "done", variant: "default" },
			{ text: "Back", action: "back", variant: "secondary" },
		],
	},
	2: {
		title: "Almost there!",
		description: "Complete account creation in your browser. Then come back here to finish up.",
		buttons: [{ text: "Back", action: "back", variant: "secondary" }],
	},
} as const

// Self-hosted build: only the "Bring my own API key" path is offered.
const BASE_USER_TYPE_SELECTIONS: UserTypeSelection[] = [
	{ title: "Bring my own API key", description: "Use AI Coder with your provider of choice", type: NEW_USER_TYPE.BYOK },
]

export function getUserTypeSelections(_hasClinePassModels: boolean): UserTypeSelection[] {
	return BASE_USER_TYPE_SELECTIONS
}
