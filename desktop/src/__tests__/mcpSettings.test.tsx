import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import '@testing-library/jest-dom'

import { McpSettings } from '../pages/McpSettings'
import { useMcpStore } from '../stores/mcpStore'
import { useSessionStore } from '../stores/sessionStore'
import { useSettingsStore } from '../stores/settingsStore'

describe('McpSettings', () => {
  beforeEach(() => {
    useSettingsStore.setState({ locale: 'en' })
    useSessionStore.setState({
      sessions: [
        {
          id: 'session-1',
          title: 'Test Session',
          createdAt: '',
          modifiedAt: '',
          messageCount: 0,
          projectPath: '/workspace/project',
          workDir: '/workspace/project',
          workDirExists: true,
        },
      ],
      activeSessionId: 'session-1',
      isLoading: false,
      error: null,
      selectedProjects: [],
      availableProjects: [],
      fetchSessions: vi.fn(),
      createSession: vi.fn(),
      deleteSession: vi.fn(),
      renameSession: vi.fn(),
      updateSessionTitle: vi.fn(),
      setActiveSession: vi.fn(),
      setSelectedProjects: vi.fn(),
    })
    useMcpStore.setState({
      servers: [],
      isLoading: false,
      error: null,
      fetchServers: vi.fn(),
      createServer: vi.fn(),
      updateServer: vi.fn(),
      deleteServer: vi.fn(),
      toggleServer: vi.fn(),
      reconnectServer: vi.fn(),
    })
  })

  it('loads only global MCP servers on mount', () => {
    const fetchServers = vi.fn()
    useMcpStore.setState({ fetchServers })

    render(<McpSettings />)

    expect(fetchServers).toHaveBeenCalledWith(undefined, '/workspace/project')
  })

  it('renders the empty state and add button', () => {
    render(<McpSettings />)

    expect(screen.getByText('MCP servers')).toBeInTheDocument()
    expect(screen.getByText('No MCP servers configured yet')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /add server/i })).toBeInTheDocument()
  })

  it('shows plugin and user MCP servers in grouped sections', () => {
    useMcpStore.setState({
      servers: [
        {
          name: 'plugin:telegram:telegram',
          scope: 'dynamic',
          transport: 'stdio',
          enabled: true,
          status: 'connected',
          statusLabel: 'Connected',
          configLocation: '/tmp/config',
          summary: 'npx @telegram/mcp',
          canEdit: false,
          canRemove: false,
          canReconnect: true,
          canToggle: true,
          config: { type: 'stdio', command: 'npx', args: ['@telegram/mcp'], env: {} },
        },
        {
          name: 'global-user',
          scope: 'user',
          transport: 'http',
          enabled: true,
          status: 'connected',
          statusLabel: 'Connected',
          configLocation: '/tmp/config',
          summary: 'https://example.com/mcp',
          canEdit: true,
          canRemove: true,
          canReconnect: true,
          canToggle: true,
          config: { type: 'http', url: 'https://example.com/mcp', headers: {} },
        },
      ],
    })

    render(<McpSettings />)

    expect(screen.getAllByText('Plugin').length).toBeGreaterThan(0)
    expect(screen.getAllByText('User').length).toBeGreaterThan(0)
    expect(screen.getByText('plugin:telegram:telegram')).toBeInTheDocument()
    expect(screen.getByText('global-user')).toBeInTheDocument()
  })
})
