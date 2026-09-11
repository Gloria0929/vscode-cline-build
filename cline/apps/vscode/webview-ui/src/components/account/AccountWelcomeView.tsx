import { useExtensionState } from "@/context/ExtensionStateContext"
import ClineLogoVariable from "../../assets/ClineLogoVariable"

/**
 * Self-hosted build: accounts, subscriptions and sign-in are removed, so this
 * view no longer offers a sign-up. It only points the user at API settings.
 */
export const AccountWelcomeView = () => {
	const { environment } = useExtensionState()

	return (
		<div className="flex flex-col items-center gap-2.5">
			<ClineLogoVariable className="size-16 mb-4" environment={environment} />
			<p className="text-(--vscode-descriptionForeground) text-center m-0">
				此版本为自托管模式，未启用账户、订阅与登录功能。请在「设置 → API 配置」中选择服务商并填写 API 密钥。
			</p>
		</div>
	)
}
