import { UpdateTerminalConnectionTimeoutResponse } from "@shared/proto/index.cline"
import { VSCodeCheckbox, VSCodeDropdown, VSCodeOption, VSCodeTextField } from "@vscode/webview-ui-toolkit/react"
import React, { useState } from "react"
import { PlatformType } from "@/config/platform.config"
import { useExtensionState } from "@/context/ExtensionStateContext"
import { usePlatform } from "@/context/PlatformContext"
import { StateServiceClient } from "../../../services/grpc-client"
import Section from "../Section"
import { updateSetting } from "../utils/settingsHandlers"

interface TerminalSettingsSectionProps {
	renderSectionHeader: (tabId: string) => JSX.Element | null
}

const TerminalSettingsSection: React.FC<TerminalSettingsSectionProps> = ({ renderSectionHeader }) => {
	const {
		shellIntegrationTimeout,
		terminalReuseEnabled,
		defaultTerminalProfile,
		availableTerminalProfiles,
		vscodeTerminalExecutionMode,
	} = useExtensionState()
	const platformConfig = usePlatform()
	const isVsCodePlatform = platformConfig.type === PlatformType.VSCODE
	const executionMode = vscodeTerminalExecutionMode ?? "vscodeTerminal"
	const isBackgroundExec = executionMode === "backgroundExec"

	const [inputValue, setInputValue] = useState((shellIntegrationTimeout / 1000).toString())
	const [inputError, setInputError] = useState<string | null>(null)

	const handleTimeoutChange = (event: Event) => {
		const target = event.target as HTMLInputElement
		const value = target.value

		setInputValue(value)

		const seconds = Number.parseFloat(value)
		if (Number.isNaN(seconds) || seconds <= 0) {
			setInputError("Please enter a positive number")
			return
		}

		setInputError(null)
		const timeoutMs = Math.round(seconds * 1000)

		StateServiceClient.updateTerminalConnectionTimeout({ timeoutMs })
			.then((response: UpdateTerminalConnectionTimeoutResponse) => {
				const timeoutMs = response.timeoutMs
				// Backend calls postStateToWebview(), so state will update via subscription
				// Just sync the input value with the confirmed backend value
				if (timeoutMs !== undefined) {
					setInputValue((timeoutMs / 1000).toString())
				}
			})
			.catch((error) => {
				console.error("Failed to update terminal connection timeout:", error)
			})
	}

	const handleInputBlur = () => {
		if (inputError) {
			setInputValue((shellIntegrationTimeout / 1000).toString())
			setInputError(null)
		}
	}

	const handleTerminalReuseChange = (event: Event) => {
		const target = event.target as HTMLInputElement
		const checked = target.checked
		updateSetting("terminalReuseEnabled", checked)
	}

	const handleExecutionModeChange = (event: Event) => {
		const target = event.target as HTMLSelectElement
		const value = target.value === "backgroundExec" ? "backgroundExec" : "vscodeTerminal"
		updateSetting("vscodeTerminalExecutionMode", value)
	}

	// Use any to avoid type conflicts between Event and FormEvent
	const handleDefaultTerminalProfileChange = (event: any) => {
		const target = event.target as HTMLSelectElement
		const profileId = target.value

		// Save immediately using the consolidated updateSettings approach
		updateSetting("defaultTerminalProfile", profileId || "default")
	}

	const profilesToShow = availableTerminalProfiles

	return (
		<div>
			{renderSectionHeader("terminal")}
			<Section>
				<div className="mb-5" id="terminal-settings-section">
					{isVsCodePlatform && (
						<div className="mb-4">
							<label className="font-medium block mb-1" htmlFor="terminal-execution-mode">
								终端执行模式
							</label>
							<VSCodeDropdown
								className="w-full"
								id="terminal-execution-mode"
								onChange={(event) => handleExecutionModeChange(event as Event)}
								value={executionMode}>
								<VSCodeOption value="vscodeTerminal">VS Code Terminal</VSCodeOption>
								<VSCodeOption value="backgroundExec">Background Exec</VSCodeOption>
							</VSCodeDropdown>
							<p className="text-xs text-[var(--vscode-descriptionForeground)] mt-1">
								选择 Coder 在 VS Code 终端还是后台进程中运行命令。
							</p>
						</div>
					)}

					{isVsCodePlatform && !isBackgroundExec && (
						<>
							<div className="mb-4">
								<div className="mb-2">
									<label className="font-medium block mb-1">Shell 集成超时（秒）</label>
									<div className="flex items-center">
										<VSCodeTextField
											className="w-full"
											onBlur={handleInputBlur}
											onChange={(event) => handleTimeoutChange(event as Event)}
											placeholder="输入超时秒数"
											value={inputValue}
										/>
									</div>
									{inputError && (
										<div className="text-(--vscode-errorForeground) text-xs mt-1">{inputError}</div>
									)}
								</div>
								<p className="text-xs text-(--vscode-descriptionForeground)">
									设置 Coder 在执行命令前等待 Shell 集成激活的时间。如果遇到终端连接超时，请增大此值。
								</p>
							</div>

							<div className="mb-4">
								<div className="flex items-center mb-2">
									<VSCodeCheckbox
										checked={terminalReuseEnabled ?? true}
										onChange={(event) => handleTerminalReuseChange(event as Event)}>
										启用积极终端复用
									</VSCodeCheckbox>
								</div>
								<p className="text-xs text-(--vscode-descriptionForeground)">
									启用后，Coder 将复用不在当前工作目录的已有终端窗口。如在终端命令后遇到任务锁定问题，请禁用此项。
								</p>
							</div>
						</>
					)}

					{/* Terminal choice affects both foreground and background execution mode. */}
					<div className="mb-4">
						<label className="font-medium block mb-1" htmlFor="default-terminal-profile">
							默认终端配置文件
						</label>
						<VSCodeDropdown
							className="w-full"
							id="default-terminal-profile"
							onChange={handleDefaultTerminalProfileChange}
							value={defaultTerminalProfile || "default"}>
							{profilesToShow.map((profile) => (
								<VSCodeOption key={profile.id} title={profile.description} value={profile.id}>
									{profile.name}
								</VSCodeOption>
							))}
						</VSCodeDropdown>
						<p className="text-xs text-(--vscode-descriptionForeground) mt-1">
								选择 Coder 使用的默认终端配置文件。“默认”使用你的 VS Code 全局设置。
							</p>
					</div>
				</div>
			</Section>
		</div>
	)
}

export default TerminalSettingsSection
