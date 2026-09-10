import { Mode } from "@shared/storage/types"
import { VSCodeLink } from "@vscode/webview-ui-toolkit/react"
import { useExtensionState } from "@/context/ExtensionStateContext"
import { DebouncedTextField } from "../common/DebouncedTextField"
import { useApiConfigurationHandlers } from "../utils/useApiConfigurationHandlers"
import VercelModelPicker from "../VercelModelPicker"

/**
 * Props for the VercelAIGatewayProvider component
 */
interface VercelAIGatewayProviderProps {
	showModelOptions: boolean
	isPopup?: boolean
	currentMode: Mode
}

/**
 * The Vercel AI Gateway provider configuration component
 */
export const VercelAIGatewayProvider = ({ showModelOptions, isPopup, currentMode }: VercelAIGatewayProviderProps) => {
	const { apiConfiguration } = useExtensionState()
	const { handleFieldChange } = useApiConfigurationHandlers()

	return (
		<div>
			<div>
				<DebouncedTextField
					initialValue={apiConfiguration?.vercelAiGatewayApiKey || ""}
					onChange={(value) => handleFieldChange("vercelAiGatewayApiKey", value)}
					placeholder="输入 API 密钥..."
					style={{ width: "100%" }}
					type="password">
					<span style={{ fontWeight: 500 }}>Vercel AI Gateway API 密钥</span>
				</DebouncedTextField>
				<p
					style={{
						fontSize: "12px",
						marginTop: "5px",
						color: "var(--vscode-descriptionForeground)",
					}}>
					此密钥仅本地存储，用于此扩展的 API 请求。
					{!apiConfiguration?.vercelAiGatewayApiKey && (
						<>
								{" "}
								您可以在此获取 Vercel AI Gateway API 密钥：{" "}
								<VSCodeLink
									href="https://vercel.com/d?to=%2F%5Bteam%5D%2F%7E%2Fai"
									style={{ display: "inline", fontSize: "inherit" }}>
									注册。
								</VSCodeLink>
							</>
					)}
				</p>
			</div>

			{showModelOptions && <VercelModelPicker currentMode={currentMode} isPopup={isPopup} />}
		</div>
	)
}
